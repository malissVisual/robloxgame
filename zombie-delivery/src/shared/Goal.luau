--!strict
-- 6.5, the goal: ONE answer to "what do I do now?" (the owner: "When I join I don't know what to do. I can't find my way
-- in anything. The UI is a terrible mess."). Pure (no Roblox services: tested by tests/goal_test.luau).
--
-- Goal.now(input) reads what the HUD already has (the Job payload of server/Jobs.luau payload(): stopLabel, step,
-- stage, handling, needed, delivered, person, piece / pieces, mission; the state's deliveries; the tutorial's phase;
-- the last delivery result while it is fresh) and returns the card client/Objective.luau shows at the top left of the
-- contract column (client/Hud.luau):
--   ▶ NEXT                      (tag: NEXT, or MISSION 3 during a mission)
--   Pick up 2 pizzas (E)        (title: the words of the moment, the server's own key in brackets)
--   Tony's Pizza · 120 m        (place and distance: the target the world marker and the minimap show)
-- and `action`, the one thing you can press right now (the HUD's pill at the lower centre: "E  Pick up pizza"), nil when
-- there is none (walking, driving, waiting: the card says it, the pill hides).
--
-- The situations (kind):
--   tutorial    Marge's first day without a job (shared/TutorialSteps.luau hint: "Talk to Marge by the job board (E)");
--               during her first job her hint for the step is the title of the job's card
--   first       no job on a new save, Marge done: "Take your first job"
--   nojob       "Take a delivery job" (press J, or the board in the depot: the world marker shows it)
--   delivered   "Delivered! +$45" for Config.Goal.ResultShown seconds after a result (failed: "Delivery failed")
--   to_pickup   on the way to the pickup: "Pick up 2 pizzas", the place and how far
--   pickup      at the pile: "Pick up 2 pizzas (E)"
--   to_drop     on the way to the drop: "Deliver to Sarah", "Apt 4C"
--   door        at the door: "Hand it over (E), or hold X to throw"
--   step        any other step at the stop (the server's words: Cargo.step, Jobs stepOf): park, open the back, load,
--               take out, carry, a piece put down, the newspaper's porch ...
--   wait        the server says to wait (the crew loads, the kids get on)
--   defend      holding out at the last drop ("HOLD OUT 0:23 · keep them off Bob!")
--   blocked     the stop is blocked ("Hold out first! Nothing gets unloaded until the area is safe.")
-- The server's step texts stay the truth: the card only shortens the travelling ones ("Walk to Sarah with the pizzas:
-- the red circle" → "Deliver to Sarah · Apt 4C") and names the pieces left at a pile.

local Config = require(script.Parent.Config)
local TutorialSteps = require(script.Parent.TutorialSteps)

local Goal = {}

export type Result = { success: boolean, total: number? }

export type Input = {
	job: { [string]: any }?, -- the Job payload (server/Jobs.luau payload()), nil without a job
	deliveries: number?, -- the state's deliveries (0: a new save)
	tutorial: string?, -- the tutorial's phase (server/Tutorial.luau: welcome, board, job, retry), nil when none runs
	result: Result?, -- the last delivery's result while it is fresh (Config.Goal.ResultShown), else nil
	distance: number?, -- studs to the target: the job's (the pile, the person, the circle) or, with no job, the board
	holding: string?, -- what your hands hold (the character's Carrying attribute)
	canThrow: boolean?, -- X throws at the door now (the ThrowTo attribute, not fragile)
	touch: boolean?, -- a touch screen: no keys in the words
}

export type Action = { key: string?, text: string, sub: string? }

export type Card = {
	title: string,
	place: string?,
	distance: number?,
	key: string?, -- the key of the moment (E, G, J ...), nil on a touch screen
	kind: string,
	tag: string, -- the small red line over the title: "NEXT", "MISSION 3"
	action: Action?, -- the pill at the lower centre: only what you can press right now
	opensBoard: boolean?, -- a click on the card opens the job board
}

local function text(value: any): string
	return if type(value) == "string" then value else ""
end

local function count(value: any): number
	return if type(value) == "number" then value else 0
end

-- "$1,250"
function Goal.money(amount: number): string
	local digits = tostring(math.floor(math.max(0, amount) + 0.5))
	local out = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return "$" .. out
end

local function sentence(words: string): string
	local lower = string.lower(words)
	return lower:sub(1, 1):upper() .. lower:sub(2)
end

local function capital(words: string): string
	return words:sub(1, 1):upper() .. words:sub(2)
end

-- The key a text names: a trailing "(E)" first, else the last one in it ("Put it down (G) and open the back (E)").
function Goal.keyOf(words: string): string?
	local last: string? = nil
	for key in string.gmatch(words, "%((%u%w?)%)") do
		last = key
	end
	return last
end

-- The words without their key: the trailing "(E)" (or the only one) goes, "Pick up a pizza (E)" → "Pick up a pizza".
function Goal.withoutKey(words: string): string
	local keys = 0
	for _ in string.gmatch(words, "%((%u%w?)%)") do
		keys += 1
	end
	if keys == 1 then
		return (string.gsub(words, "%s*%(%u%w?%)", "", 1))
	end
	return (string.gsub(words, "%s*%(%u%w?%)%s*$", ""))
end

-- A touch screen has no keys: every "(E)" goes (the prompts are tapped), "hold X" becomes the THROW button.
local function forTouch(words: string): string
	local out = string.gsub(words, "%s*%(%u%w?%)", "")
	out = string.gsub(out, "hold X to throw", "tap THROW")
	return out
end

-- A stop's label (server/Jobs.luau newStop): "DELIVER to Sarah, Apt 4C" → "Deliver", "to", "Sarah, Apt 4C";
-- "PICK UP at Tony's Pizza" → "Pick up", "at", "Tony's Pizza"; "TOSS the paper at Elm St 12" → "Toss the paper", "at",
-- "Elm St 12"; "UNLOAD AT THE NEW HOME, 42 Maple St" → "Unload at the new home", nil, "42 Maple St". The shouted words
-- are the action, the rest the place.
function Goal.parseLabel(label: string): (string, string?, string)
	local words = string.split(label, " ")
	local cut = #words + 1
	for index, word in words do
		if string.upper(word) ~= word or string.match(word, "^%d") then
			cut = index
			break
		end
	end
	local action = (string.gsub(table.concat(words, " ", 1, cut - 1), ",$", ""))
	local joiner: string? = nil
	local first = string.lower(words[cut] or "")
	local rest = table.concat(words, " ", cut)
	if first == "at" or first == "to" or first == "for" then
		joiner = first
		rest = table.concat(words, " ", cut + 1)
	end
	-- "DELIVER THE AMMO TO" + "Military Base": the joiner shouted with the action
	for _, tail in { "TO", "AT", "FOR" } do
		if joiner == nil and #action > #tail + 1 and string.sub(action, -(#tail + 1)) == " " .. tail then
			joiner = string.lower(tail)
			action = string.sub(action, 1, -(#tail + 2))
		end
	end
	-- "PICK UP the papers at Elm St": the quiet words before "at" still belong to the action
	if joiner == nil then
		local before, after = string.match(rest, "^(.-) at (.+)$")
		if before and after and before ~= "" then
			action ..= " " .. before
			joiner = "at"
			rest = after
		end
	end
	return sentence(action), joiner, rest
end

-- The pieces still to pick up here: "2 pizzas", "a pizza".
local function pieces(job: { [string]: any }, left: number): string
	local one = text(job.piece)
	local many = text(job.pieces)
	if one == "" then
		one = "piece"
	end
	if many == "" then
		many = one .. "s"
	end
	if left <= 1 then
		return `{if string.find("aeiou", string.lower(one:sub(1, 1)), 1, true) then "an" else "a"} {one}`
	end
	return `{left} {many}`
end

-- Where the stop is and what the trip there is called: "Pick up 2 pizzas" / "Tony's Pizza", "Deliver to Sarah" / "Apt
-- 4C". Also the person and the place for the door's card.
local function trip(job: { [string]: any }): (string, string?)
	local label = text(job.stopLabel)
	if label == "" then
		label = text(job.cargo)
	end
	local action, joiner, rest = Goal.parseLabel(label)
	local pickup = job.stage == "pickup"
	local left = math.max(1, count(job.needed) - count(job.delivered))
	if pickup and string.find(string.lower(action), "pick up", 1, true) and count(job.needed) > 0 then
		local prefix = string.match(action, "^(.-)[Pp]ick up") or ""
		return `{prefix}{if prefix == "" then "Pick up" else "pick up"} {pieces(job, left)}`, if rest ~= "" then rest else nil
	end
	local who, where = string.match(rest, "^([^,]+),%s*(.+)$")
	if joiner == "to" and who and where then
		return `{action} to {who}`, where
	end
	if action == "" then
		action = if pickup then "Pick up" else "Deliver"
	end
	if joiner == "to" or joiner == "for" then
		return `{action} {joiner} {rest}`, nil
	end
	return action, if rest ~= "" then rest else nil
end

local function plainAction(words: string, touch: boolean?): Action?
	local key = Goal.keyOf(words)
	if key == nil then
		return nil
	end
	return { key = if touch then nil else key, text = if touch then forTouch(words) else Goal.withoutKey(words) }
end

-- The card for a running job.
local function forJob(job: { [string]: any }, input: Input): Card
	local touch = input.touch == true
	local mission = job.mission
	local tag = if type(mission) == "table" and mission.number then `MISSION {mission.number}` else "NEXT"
	local title, place = trip(job)
	local step = text(job.step)
	local handling = text(job.handling)
	local pickup = job.stage == "pickup"
	local function card(kind: string, words: string, where: string?, distance: number?, action: Action?): Card
		local shown = if touch then forTouch(words) else words
		return {
			title = shown,
			place = where,
			distance = distance,
			key = if touch then nil else Goal.keyOf(words),
			kind = kind,
			tag = tag,
			action = action,
		}
	end
	-- Holding out at the last drop, and a blocked stop: the server's words, the clock in them.
	local hold, why = string.match(step, "^HOLD OUT ([%d:]+) · (.+)$")
	if hold and why then
		return card("defend", `Hold out {hold}`, capital(why), nil, nil)
	end
	local first, rest = string.match(step, "^(Hold out first!)%s*(.*)$")
	if first then
		return card("blocked", first, if rest ~= "" then rest else nil, nil, nil)
	end
	if step == "" or ((handling == "drive" or handling == "") and Goal.keyOf(step) == nil) then
		-- On the way: what the trip is for, where, how far.
		return card(if pickup then "to_pickup" else "to_drop", title, place, input.distance, nil)
	end
	if string.match(step, "^Wait") then
		return card("wait", step, place, input.distance, nil)
	end
	-- At the pile: the pieces left, E picks one up.
	if pickup and job.looseAt == nil and (string.match(step, "^Pick up an? ") or string.match(step, "^Pick up another ") or string.match(step, "^Pick up the bundle")) then
		local piece = text(job.piece)
		return card("pickup", `{title} (E)`, place, input.distance, {
			key = if touch then nil else "E",
			text = if piece ~= "" then `Pick up {piece}` else "Pick up",
		})
	end
	-- At the door: hand it over (E), or throw it (X: the server's ThrowTo).
	if not pickup and (string.match(step, "^Hand ") or string.match(step, "^Nobody's home")) then
		local nobody = string.match(step, "^Nobody's home") ~= nil
		local them = string.match(step, "^Hand them") ~= nil or string.match(step, "leave them") ~= nil
		local verb = if nobody then `Leave {if them then "them" else "it"} at the door` else `Hand {if them then "them" else "it"} over`
		local person = text(job.person)
		local where = if person ~= "" and place then `{person} · {place}` elseif person ~= "" then person else place
		local throw = input.canThrow == true
		return card("door", `{verb} (E){if throw then ", or hold X to throw" else ""}`, where, input.distance, {
			key = if touch then nil else "E",
			text = verb,
			sub = if throw then (if touch then "or tap THROW" else "or hold X to throw") else nil,
		})
	end
	-- Every other step at the stop: the server's words (park, open the back, load, take out, carry ...).
	return card("step", step, place, input.distance, plainAction(step, touch))
end

-- What to do now (see the header): always a card.
function Goal.now(input: Input): Card
	local touch = input.touch == true
	local job = input.job
	if type(job) == "table" then
		local card = forJob(job, input)
		-- Marge's first job (the tutorial runs): her hint for the step is the title (shared/TutorialSteps.luau, read
		-- as client/TutorialUi.luau reads it; its strip shows only FIRST DAY and SKIP while a job runs). The place, the
		-- distance and the pill stay the job's.
		if input.tutorial ~= nil then
			local hint = TutorialSteps.hint(TutorialSteps.jobStep(job), job)
			if hint ~= "" then
				card.title = if touch then TutorialSteps.forTouch(hint) else hint
				card.key = if touch then nil else Goal.keyOf(hint)
			end
		end
		return card
	end
	-- Something in your hands without a job: put it down (G).
	local holding: Action? = nil
	if input.holding then
		holding = if input.holding == "horse" then { key = if touch then nil else "G", text = "Let it go" } else { key = if touch then nil else "G", text = "Put it down" }
	end
	local result = input.result
	if result then
		if result.success then
			return {
				title = `Delivered! +{Goal.money(result.total or 0)}`,
				place = if touch then "Tap here for the next job" else "Press J for the next job",
				key = if touch then nil else "J",
				kind = "delivered",
				tag = "NEXT",
				action = holding,
				opensBoard = true,
			}
		end
		return {
			title = "Delivery failed",
			place = if touch then "Tap here for another job" else "Press J for another job",
			key = if touch then nil else "J",
			kind = "failed",
			tag = "NEXT",
			action = holding,
			opensBoard = true,
		}
	end
	-- Marge's first day: her own hint (shared/TutorialSteps.luau) while she waits for you.
	local phase = input.tutorial
	if phase == "welcome" or phase == "board" or phase == "retry" then
		local hint = TutorialSteps.hint(phase, nil)
		if hint ~= "" then
			return {
				title = if touch then TutorialSteps.forTouch(hint) else hint,
				place = if phase == "board" then "Job board" else `{Config.Tutorial.NpcName} · the depot`,
				distance = input.distance,
				key = if touch then nil else Goal.keyOf(hint),
				kind = "tutorial",
				tag = "NEXT",
				action = holding,
				opensBoard = phase == "board",
			}
		end
	end
	local first = (input.deliveries or 0) <= 0
	return {
		title = if first then "Take your first job" else "Take a delivery job",
		place = if touch then "Tap here · or the job board" else "Press J · or the job board",
		distance = input.distance,
		key = if touch then nil else "J",
		kind = if first then "first" else "nojob",
		tag = "NEXT",
		action = holding,
		opensBoard = true,
	}
end

return Goal
