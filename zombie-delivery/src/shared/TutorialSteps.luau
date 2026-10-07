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
-- the shops and to save up for a bike (level 2). 6.6: bigger bags at ZDC Bags, the kiosk by the spawn (no backpacks).
-- 5.7: the van's hints are gone (a new player never has a car on the first day: every job step has the walking hint,
-- "Ride" on a bike). After the first delivery her last page offers SHOW ME AROUND, a short tour (TutorialSteps.Tour,
-- tourDialog): the ZDC RIDE dock by the depot, the nearest bus stop (each on the GPS: client/TutorialUi.luau), then
-- Q → BOARD. Every page can skip the rest.
-- 6.5, a tutorial that shows instead of talks: her welcome is one short page (take a job, deliver it, get paid; follow
-- NEXT at the top left), the run has no pages of hers (the HUD's goal card shows TutorialSteps.hint: short imperative
-- goals, "Pick up the letters at the Post Office", "Deliver to Sarah · Apt 4C", "Hand it over (E)"), a failed run
-- one page, and the done screen one page with the reward and where to go next (J for a job, Q → SHOP for the shops),
-- SHOW ME AROUND (the tour, still optional) or CLOSE. The tour's last page points to JOBS (the phone's 6.5 tile).
-- 6.7, a tutorial that never annoys (the owner: "It should simply show with an arrow where things are in the menu,
-- then that you take one job, and you either say yes or skip tutorial. But don't automatically give a job."):
--   * her welcome (one page, it shows on its own after PLAY): SHOW ME (the phone and the arrow tour) / SKIP TUTORIAL;
--   * the arrow tour of the screen (TutorialSteps.ScreenTour, client/TutorialUi.luau drives it, client/TutorialArrow.luau
--     draws it): one stop a thing on the screen, a one-sentence caption each (TutorialSteps.tourLine), NEXT / SKIP
--     TUTORIAL; where the arrow sits by its target is TutorialSteps.placeArrow (pure, tested);
--   * at its end one page, "ready": TAKE A JOB (the phone's JOBS, any job you like) / SKIP TUTORIAL;
--   * then no page of hers during play: the first delivery of ANY job pays Config.Tutorial.Reward with a toast (the
--     server), a failed one goes back to "board" (the goal card's "Take your first job (J)"). Her done page, the
--     "retry" and "board" pages are gone; talking to her (E) while you wait shows "say" with OPEN THE BOARD.
--   The 5.7 world tour (TutorialSteps.Tour: the dock, the bus stop, the board) stays for SHOW ME AROUND in the phone's
--   SETTINGS (MORE).

local Config = require(script.Parent.Config)

local TutorialSteps = {}

export type Dialog = {
	speaker: string, -- small caps over the line ("MARGE · DISPATCHER")
	pages: { string },
	primary: string, -- the last page's action ("LET'S GO"); the earlier pages say CONTINUE
	secondary: string?, -- a quiet second action on every page ("SKIP TUTORIAL", "LATER")
}

-- The phases the server sends (server/Tutorial.luau); "phone" (5.0) is a message, not a phase. 6.7: "tour" (the arrow
-- tour runs); "retry" is never sent any more (a failed run goes back to "board"), the clients still read it.
TutorialSteps.Phases = { "welcome", "tour", "board", "job", "retry", "done", "say", "phone" }

-- 5.7: the tour after the first delivery, in order.
TutorialSteps.Tour = { "dock", "bus", "board" }

-- The job's steps (TutorialSteps.jobStep), in the order they come.
TutorialSteps.JobSteps = { "drive_pickup", "pickup", "pickup_more", "carry", "loose", "drive_drop", "unload", "handover" }

-- Marge's speech bubbles over her head (server/Tutorial.luau, Npcs.say). 6.7: no "give" (she gives no job).
TutorialSteps.Bubble = {
	tour = "Follow the arrows, hon.",
	board = "Take any job you like, hon. Press J.",
	busy = "You're on a job! Get going.",
	done = "Jobs are on the board. Good luck out there.",
}

-- 6.7: the arrow tour of the screen, in order (client/TutorialUi.luau). target: what the arrow points at, found by name
-- (next: the HUD's NEXT card, phone: PHONE [Q] top right, jobsApp / mapApp / shopApp / bagApp: the phone's tiles,
-- hotbar: the bottom bar, minimap: the minimap); side: where the arrow and the caption sit by it (another side when
-- that one has no room: placeArrow); phone: "open" the tour opens the phone for the stop, "closed" puts it away;
-- text: the caption (one sentence), touch: a touch screen's own (else forTouch(text)).
export type TourStop = { id: string, target: string, side: string, phone: string, text: string, touch: string? }

TutorialSteps.ScreenTour = {
	{ id = "next", target = "next", side = "right", phone = "closed", text = "This card always tells you what to do next." },
	{ id = "phone", target = "phone", side = "left", phone = "closed", text = "Your phone (Q): jobs, map, shops, everything." },
	{ id = "jobs", target = "jobsApp", side = "left", phone = "open", text = "Take jobs here." },
	{ id = "map", target = "mapApp", side = "left", phone = "open", text = "The map and GPS." },
	{ id = "shop", target = "shopApp", side = "left", phone = "open", text = "Shops: tap one to get GPS there." },
	{ id = "bag", target = "bagApp", side = "left", phone = "open", text = "Your bag and items." },
	{
		id = "hotbar",
		target = "hotbar",
		side = "above",
		phone = "closed",
		text = "1 fists, 2 your bag, 3 your gun, 4–8 items.",
		touch = "Tap your fists, your bag, your gun, then your items.",
	},
	{
		id = "minimap",
		target = "minimap",
		side = "right",
		phone = "closed",
		text = "The minimap: M opens the big map.",
		touch = "The minimap: EXPAND opens the big map.",
	},
} :: { TourStop }

-- 6.7: a tour stop's caption for this screen (a touch screen names no keys).
function TutorialSteps.tourLine(stop: TourStop, touch: boolean): string
	if touch then
		return stop.touch or TutorialSteps.forTouch(stop.text)
	end
	return stop.text
end

-- 6.7: where the tour's arrow and caption go (client/TutorialArrow.luau, every frame; px in the tour's ScreenGui).
--   target   the thing pointed at { x, y, w, h }      screen  { w, h }
--   side     the stop's side: the arrow sits left of / right of / above / below the target ("left": it points right)
--   length   the arrow's length, travel how far it bounces back, gap between the target and its tip
--   caption  the caption box { w, h }, margin the screen's edge kept free (8)
-- The stop's side is kept while it has the room for the gap, the arrow, its bounce and the caption; else the side with
-- the most room to spare (left, right, above, below on a tie). Returns the side, the arrow's Rotation (it is drawn
-- pointing down: 0 down, 90 left, 180 up, -90 right), its centre with its tip at the gap (arrowX / arrowY), the unit
-- vector toward the target (dirX / dirY: the bounce goes against it) and the caption's top left, kept on the screen.
export type ArrowPlace = {
	side: string,
	rotation: number,
	arrowX: number,
	arrowY: number,
	dirX: number,
	dirY: number,
	captionX: number,
	captionY: number,
}

export type ArrowInput = {
	target: { x: number, y: number, w: number, h: number },
	screen: { w: number, h: number },
	side: string,
	length: number,
	travel: number,
	gap: number,
	caption: { w: number, h: number },
	margin: number?,
}

local SIDES = { "left", "right", "above", "below" }

function TutorialSteps.placeArrow(input: ArrowInput): ArrowPlace
	local t, screen, caption = input.target, input.screen, input.caption
	local m = input.margin or 8
	local reach = input.gap * 2 + input.length + input.travel -- the gap, the arrow and its bounce, a gap
	local function room(side: string): number
		if side == "left" then
			return t.x - m
		elseif side == "right" then
			return screen.w - (t.x + t.w) - m
		elseif side == "above" then
			return t.y - m
		end
		return screen.h - (t.y + t.h) - m
	end
	local function spare(side: string): number
		local need = reach + (if side == "left" or side == "right" then caption.w else caption.h)
		return room(side) - need
	end
	local side = if table.find(SIDES, input.side) then input.side else "below"
	if spare(side) < 0 then
		local best = -math.huge
		for _, candidate in SIDES do
			local value = spare(candidate)
			if value > best then
				best, side = value, candidate
			end
		end
	end
	local cx, cy = t.x + t.w / 2, t.y + t.h / 2
	local half = input.length / 2
	local beyond = input.length + input.travel + input.gap -- from the tip to the caption's near edge
	local out: ArrowPlace
	if side == "left" then
		local tip = t.x - input.gap
		out = { side = side, rotation = -90, arrowX = tip - half, arrowY = cy, dirX = 1, dirY = 0, captionX = tip - beyond - caption.w, captionY = cy - caption.h / 2 }
	elseif side == "right" then
		local tip = t.x + t.w + input.gap
		out = { side = side, rotation = 90, arrowX = tip + half, arrowY = cy, dirX = -1, dirY = 0, captionX = tip + beyond, captionY = cy - caption.h / 2 }
	elseif side == "above" then
		local tip = t.y - input.gap
		out = { side = side, rotation = 0, arrowX = cx, arrowY = tip - half, dirX = 0, dirY = 1, captionX = cx - caption.w / 2, captionY = tip - beyond - caption.h }
	else
		local tip = t.y + t.h + input.gap
		out = { side = side, rotation = 180, arrowX = cx, arrowY = tip + half, dirX = 0, dirY = -1, captionX = cx - caption.w / 2, captionY = tip + beyond }
	end
	out.captionX = math.clamp(out.captionX, m, math.max(m, screen.w - m - caption.w))
	out.captionY = math.clamp(out.captionY, m, math.max(m, screen.h - m - caption.h))
	return out
end

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
		return "Take your first job (J)" -- 6.7: any job (the board or the phone's JOBS), she gives none
	elseif step == "retry" then
		return "Take another job (J)" -- 6.7: (no longer sent: a failed run goes back to "board")
	end
	return "" -- (6.7: "tour": the arrows say it; the goal card says "Take your first job")
end

-- Marge's dialog for a phase the server sent (data: reward, text, board for say), nil for a phase without one.
-- 6.7: only two of hers come on their own: the welcome (after PLAY) and "ready" (the arrow tour's end, the client's);
-- "skip" asks before the strip's SKIP; "say" answers when you talk to her (E). Nothing during play: board, job,
-- retry and done have none (the first delivery's reward is a toast).
function TutorialSteps.dialog(phase: string, data: { [string]: any }?): Dialog?
	local info: { [string]: any } = data or {}
	local name = Config.Tutorial.NpcName
	local reward = if type(info.reward) == "number" then math.floor(info.reward) else Config.Tutorial.Reward
	if phase == "welcome" then
		-- 6.7: one page: SHOW ME (her phone and the arrow tour) or SKIP TUTORIAL; no job of hers
		return {
			speaker = speaker(false),
			pages = { `Hi, I'm {name}, dispatch. You're a courier now: take jobs, deliver, get paid. Let me show you around in 20 seconds.` },
			primary = "SHOW ME",
			secondary = "SKIP TUTORIAL",
		}
	elseif phase == "ready" then
		-- 6.7 (client only): the arrow tour's end. TAKE A JOB opens the phone's JOBS: you pick any job.
		return {
			speaker = speaker(false),
			pages = { `Ready? Take your first job, any one you like: your first delivery earns +${reward} from me.` },
			primary = "TAKE A JOB",
			secondary = "SKIP TUTORIAL",
		}
	elseif phase == "skip" then
		-- (client only: the strip's SKIP asks first, a skipped tutorial does not come back)
		return {
			speaker = speaker(false),
			pages = { "Skip the tutorial? There's no first-delivery bonus then." },
			primary = "SKIP TUTORIAL",
			secondary = "KEEP IT",
		}
	elseif phase == "say" then
		if info.board == true then
			-- 6.7: you talked to her while she waits for your first job
			return {
				speaker = speaker(false),
				pages = { `Take any job you like: the board (J) or JOBS in your phone. Your first delivery earns +${reward} from me.` },
				primary = "OPEN THE BOARD",
				secondary = "LATER",
			}
		end
		return {
			speaker = speaker(false),
			pages = { text(info.text, TutorialSteps.Bubble.done) },
			primary = "OK",
		}
	end
	return nil -- (6.5: job; 6.7: tour, board, retry, done: no pages during play)
end

-- 5.7, the tour after the first delivery (TutorialSteps.Tour): one short page a stop, the place on your GPS
-- (client/TutorialUi.luau). info.dock: the dock's name, info.stop: the bus stop's. Nil for an unknown step.
-- 6.7: SHOW ME AROUND in the phone's SETTINGS runs it (the first day has the arrow tour of the screen instead).
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
