--!strict
-- 10.1 THE HELPERS' CREW (Config.Crew; the owner: "you'll be able to get different employees who can do something
-- different. There don't have to be many, but Danny will be the base, so I'd cancel having to buy him. Because you'll
-- have to get them somehow. And maybe when one dies, then … something"): the rules of a player's crew of NPC helpers,
-- pure (no Roblox: tests/crewrules_test.luau). server/HelperCrew.luau keeps the crews and runs the rescues, the downs and
-- the hospital with them (its hooks in server/MoveHelper.luau make each kind carry, walk and fight its own way);
-- client/CrewUi.luau shows the CREW window.
--
-- The kinds (Config.Crew.Kinds, in Config.Crew.Order): Danny (the mover: free, everybody's from the start), Bruno (the
-- strong one: a piece for two alone, slowly), Zip (the quick one: one-hand and small pieces only, fast), Gus (the guard:
-- carries nothing, fights the zombies), Lucy (the finder: small pieces; the party sees the Epic and Legendary loot
-- through walls). Each is a MoveHelper of that kind; one comes into a run: its host's pick (Danny by default).
--   CrewRules.kinds() -> { id }            the kinds in the window's order
--   CrewRules.def(id) -> CrewKind?         a kind's Config entry (nil: no such kind)
--   CrewRules.title(id) / she(id) / he(id, big?) / his(id) / him(id)   his name tag's second line ("Strong · ZDC
--                                          Moving"), her words
--   CrewRules.look(id) -> NpcLooks.Look    how he is dressed: the mover's look with his own shirt, hat, apron …
-- What he does (server/MoveHelper.luau's hooks through server/HelperCrew.luau):
--   CrewRules.mayCarry(id, class, weight) -> (ok, why?)   may he take a piece of that class ("hand" | "both" | "pair")
--                                          and weight: why "nothing" (he carries nothing: Gus), "hand", "heavy" (a
--                                          both-hands piece over his Carry.Both), "pair" (a piece for two: never his)
--   CrewRules.lifts(id)                    does he come to lift a piece for two with you (Carry.Pair "with" | "alone")
--   CrewRules.solo(id)                     does he carry a piece for two alone (Carry.Pair "alone": Bruno)
--   CrewRules.pace(id, solo?) -> ×         his walk × this (Speed; × Solo while he carries a piece for two alone)
--   CrewRules.health(id) -> hp             his full health
--   CrewRules.carryText(id)                the window's words for what he carries
-- The save (profile.crew: server/PlayerData.luau): { have = { id }, pick = id, hospital = { [id] = os.time() until } }.
--   CrewRules.empty() -> Saved             a new player's: Danny alone, Danny picked
--   CrewRules.clean(raw) -> Saved          a saved crew checked: known kinds only, once each, Danny always first; the
--                                          pick one of them (else Danny); hospital times of the crew's own, whole numbers
--   CrewRules.fromSave(saved) -> Saved     the migration: a real save (money in it) written with the flag
--                                          (Config.Crew.Flag) keeps its crew (clean); anything else, an older save too
--                                          (nothing about the 8.3 – 10.0 hire was ever saved), the empty one: Danny
--   CrewRules.toSave(crew) -> table        what a save writes (a copy)
--   CrewRules.has(crew, id) / add(crew, id) -> new?   in the crew / one more (true when he is new)
-- The hospital (a helper out of a run: Config.Crew.Hospital; `now` is os.time()):
--   CrewRules.toHospital(crew, id, now, factor?)   out of the crew until now + Seconds (10.4: × factor, the owner's
--                                          upgrade tree's Good doctors: hospitalSeconds(factor))
--   CrewRules.hospitalLeft(crew, id, now) -> s    seconds left (0: not in hospital)
--   CrewRules.ready(crew, id, now)         in the crew and not in hospital
--   CrewRules.heal(crew, now) -> changed   the hospital times past dropped
--   CrewRules.dischargePrice(left) -> $    out early: Base + PerMinute × the minutes left (whole minutes up), to Round
-- Who comes:
--   CrewRules.pickCheck(crew, id) -> "ok" | "unknown" | "locked" (not in your crew) | "same"
--   CrewRules.comes(crew, now) -> (id?, instead)   the helper who comes into your run: your pick when he is ready, else
--                                          (instead true) the first ready one in the order; nil: nobody (all in hospital)
-- The rescue (a helper trapped in a run's house: Config.Crew.Rescue; who gets him: the whole party):
--   CrewRules.rescueChance(difficulty) -> 0 … 1   a run's odds of a trapped helper
--   CrewRules.rescueRoll(difficulty, roll) -> bool   roll (0 … 1) under the odds
--   CrewRules.rescueKind(missing, roll) -> id      who is trapped: the kind the most of the party lack (missing: id → how
--                                          many lack him; ties by the roll); nobody lacks one: any kind but Danny (the
--                                          bonus for everybody)
--   CrewRules.rescueBonus(difficulty) -> $ the money a party player who has him already gets instead
-- Down in a run (Config.Crew.Down; `downAt`, `now` on one clock):
--   CrewRules.downLeft(downAt, now) -> s   seconds left to revive him (0: out)
--   CrewRules.reviveHealth(id) -> hp       his health when he gets up (Health × Down.Health)
-- The window:
--   CrewRules.view(crew, now) -> { Row }   every kind: { id, name, icon, role, ability, carry, have, pick, state ("ready" |
--                                          "hospital" | "locked"), left (s), price (the discharge) }
--   CrewRules.clock(seconds) -> "m:ss"; CrewRules.money(n) -> "$1,234"
local Config = require(script.Parent.Config)
local NpcLooks = require(script.Parent.NpcLooks)
local UpgradeRules = require(script.Parent.UpgradeRules) -- (the money's words)

local CrewRules = {}

CrewRules.money = UpgradeRules.money -- "$1,234"

local C = Config.Crew

export type Saved = { have: { string }, pick: string, hospital: { [string]: number } }
export type Row = {
	id: string,
	name: string,
	icon: string,
	role: string,
	ability: string,
	carry: string,
	have: boolean,
	pick: boolean,
	state: string,
	left: number,
	price: number,
}

local function whole(n: any): boolean
	return type(n) == "number" and n == n and n == math.floor(n) and math.abs(n) < 2 ^ 53
end

function CrewRules.kinds(): { string }
	return C.Order
end

function CrewRules.def(id: any): Config.CrewKind?
	if type(id) ~= "string" then
		return nil
	end
	return C.Kinds[id]
end

local function defOr(id: any): Config.CrewKind
	return CrewRules.def(id) or C.Kinds[C.Default]
end

function CrewRules.title(id: any): string
	return `{defOr(id).Role} · {Config.MoveHelper.Title}`
end

function CrewRules.she(id: any): boolean
	return defOr(id).She == true
end

-- "he" / "she" and "his" / "her" (capitalised with `big`).
function CrewRules.he(id: any, big: boolean?): string
	local word = if CrewRules.she(id) then "she" else "he"
	return if big then string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2) else word
end

function CrewRules.his(id: any): string
	return if CrewRules.she(id) then "her" else "his"
end

function CrewRules.him(id: any): string
	return if CrewRules.she(id) then "her" else "him"
end

function CrewRules.look(id: any): NpcLooks.Look
	local def = defOr(id)
	local look = NpcLooks.look("mover", def.Name, CrewRules.title(id))
	for key, value in def.Look do
		(look :: any)[key] = value
	end
	return look
end

-- ── What he carries ────────────────────────────────────────────────────────

function CrewRules.mayCarry(id: any, class: string, weight: number): (boolean, string?)
	local carry = defOr(id).Carry
	if not carry.Hand and carry.Both <= 0 and carry.Pair == false then
		return false, "nothing"
	elseif class == "pair" then
		return carry.Pair ~= false, if carry.Pair == false then "pair" else nil
	elseif class == "hand" then
		return carry.Hand, if carry.Hand then nil else "hand"
	end
	local w = if type(weight) == "number" and weight == weight then weight else 10
	if w > carry.Both then
		return false, "heavy"
	end
	return true, nil
end

function CrewRules.lifts(id: any): boolean
	local pair = defOr(id).Carry.Pair
	return pair == "with" or pair == "alone"
end

function CrewRules.solo(id: any): boolean
	return defOr(id).Carry.Pair == "alone"
end

function CrewRules.pace(id: any, solo: boolean?): number
	local def = defOr(id)
	return def.Speed * (if solo then def.Solo else 1)
end

function CrewRules.health(id: any): number
	return defOr(id).Health
end

function CrewRules.carryText(id: any): string
	local carry = defOr(id).Carry
	if not carry.Hand and carry.Both <= 0 and carry.Pair == false then
		return "Carries nothing"
	end
	local parts: { string } = {}
	if carry.Hand then
		table.insert(parts, "one-hand")
	end
	if carry.Both >= 10 then
		table.insert(parts, "both-hands")
	elseif carry.Both > 0 then
		table.insert(parts, "small both-hands")
	end
	local text = "Carries " .. table.concat(parts, " and ") .. " pieces"
	if carry.Pair == "alone" then
		text ..= "; two-person ones alone"
	elseif carry.Pair == "with" then
		text ..= "; two-person ones with you"
	end
	return text
end

-- ── The save ───────────────────────────────────────────────────────────────

function CrewRules.empty(): Saved
	return { have = { C.Default }, pick = C.Default, hospital = {} }
end

function CrewRules.clean(raw: any): Saved
	local crew = CrewRules.empty()
	if type(raw) ~= "table" then
		return crew
	end
	local listed: { [string]: boolean } = {}
	if type(raw.have) == "table" then
		for _, id in raw.have do
			if type(id) == "string" and C.Kinds[id] then
				listed[id] = true
			end
		end
	end
	for _, id in C.Order do
		if listed[id] and id ~= C.Default then
			table.insert(crew.have, id)
		end
	end
	if type(raw.pick) == "string" and table.find(crew.have, raw.pick) then
		crew.pick = raw.pick
	end
	if type(raw.hospital) == "table" then
		for id, at in raw.hospital do
			if type(id) == "string" and table.find(crew.have, id) and whole(at) and at > 0 then
				crew.hospital[id] = at
			end
		end
	end
	return crew
end

function CrewRules.fromSave(saved: any): Saved
	if type(saved) ~= "table" or saved.money == nil or saved[C.Flag] ~= true then
		return CrewRules.empty()
	end
	return CrewRules.clean(saved.crew)
end

function CrewRules.toSave(crew: Saved): { [string]: any }
	local hospital: { [string]: number } = {}
	for id, at in crew.hospital do
		hospital[id] = at
	end
	return { have = table.clone(crew.have), pick = crew.pick, hospital = hospital }
end

function CrewRules.has(crew: Saved, id: any): boolean
	return type(id) == "string" and table.find(crew.have, id) ~= nil
end

function CrewRules.add(crew: Saved, id: any): boolean
	if not CrewRules.def(id) or CrewRules.has(crew, id) then
		return false
	end
	local ordered: { string } = {}
	for _, kind in C.Order do -- (the window's order kept)
		if kind == id or table.find(crew.have, kind) then
			table.insert(ordered, kind)
		end
	end
	table.clear(crew.have)
	for _, kind in ordered do
		table.insert(crew.have, kind)
	end
	return true
end

-- ── The hospital ───────────────────────────────────────────────────────────

-- (10.4: × `factor`, the owner's upgrade tree's Good doctors: UpgradeRules.effect(levels, "hospital"); none: 1)
function CrewRules.toHospital(crew: Saved, id: string, now: number, factor: number?)
	if CrewRules.has(crew, id) then
		crew.hospital[id] = math.floor(now) + CrewRules.hospitalSeconds(factor)
	end
end

-- 10.4: a hospital stay's seconds (Hospital.Seconds × factor, 0.1 … 1 of it; none: all of it).
function CrewRules.hospitalSeconds(factor: number?): number
	local f = if type(factor) == "number" and factor == factor then math.clamp(factor, 0.1, 1) else 1
	return math.max(1, math.floor(C.Hospital.Seconds * f + 0.5))
end

function CrewRules.hospitalLeft(crew: Saved, id: any, now: number): number
	local at = if type(id) == "string" then crew.hospital[id] else nil
	if type(at) ~= "number" then
		return 0
	end
	return math.max(0, at - now)
end

function CrewRules.ready(crew: Saved, id: any, now: number): boolean
	return CrewRules.has(crew, id) and CrewRules.hospitalLeft(crew, id, now) <= 0
end

function CrewRules.heal(crew: Saved, now: number): boolean
	local changed = false
	for id, at in crew.hospital do
		if at <= now then
			crew.hospital[id] = nil
			changed = true
		end
	end
	return changed
end

function CrewRules.dischargePrice(left: number): number
	if type(left) ~= "number" or left ~= left or left <= 0 then
		return 0
	end
	local h = C.Hospital
	local price = h.Base + h.PerMinute * math.ceil(left / 60)
	return math.max(h.Round, math.floor(price / h.Round + 0.5) * h.Round)
end

-- ── Who comes ──────────────────────────────────────────────────────────────

function CrewRules.pickCheck(crew: Saved, id: any): string
	if not CrewRules.def(id) then
		return "unknown"
	elseif not CrewRules.has(crew, id) then
		return "locked"
	elseif crew.pick == id then
		return "same"
	end
	return "ok"
end

function CrewRules.comes(crew: Saved, now: number): (string?, boolean)
	if CrewRules.ready(crew, crew.pick, now) then
		return crew.pick, false
	end
	for _, id in C.Order do
		if CrewRules.ready(crew, id, now) then
			return id, true
		end
	end
	return nil, false
end

-- ── The rescue ─────────────────────────────────────────────────────────────

local function difficultyOf(difficulty: any): string
	return if type(difficulty) == "string" and C.Rescue.Chance[difficulty] then difficulty else Config.Runs.Default
end

function CrewRules.rescueChance(difficulty: any): number
	return math.clamp(C.Rescue.Chance[difficultyOf(difficulty)] or 0, 0, 1)
end

function CrewRules.rescueRoll(difficulty: any, roll: number): boolean
	return roll < CrewRules.rescueChance(difficulty)
end

function CrewRules.rescueKind(missing: { [string]: number }, roll: number): string
	local best, tied = 0, {} :: { string }
	for _, id in C.Order do
		local n = missing[id]
		if id ~= C.Default and type(n) == "number" and n > 0 then
			if n > best then
				best, tied = n, { id }
			elseif n == best then
				table.insert(tied, id)
			end
		end
	end
	if #tied == 0 then
		for _, id in C.Order do
			if id ~= C.Default then
				table.insert(tied, id)
			end
		end
	end
	local r = if type(roll) == "number" and roll == roll then math.clamp(roll, 0, 0.999999) else 0
	return tied[math.floor(r * #tied) + 1]
end

function CrewRules.rescueBonus(difficulty: any): number
	return C.Rescue.Bonus[difficultyOf(difficulty)] or 0
end

-- ── Down in a run ──────────────────────────────────────────────────────────

function CrewRules.downLeft(downAt: number, now: number): number
	return math.max(0, downAt + C.Down.Seconds - now)
end

function CrewRules.reviveHealth(id: any): number
	return math.max(1, math.floor(CrewRules.health(id) * C.Down.Health + 0.5))
end

-- ── The window ─────────────────────────────────────────────────────────────

function CrewRules.view(crew: Saved, now: number): { Row }
	local rows: { Row } = {}
	for _, id in C.Order do
		local def = C.Kinds[id]
		local have = CrewRules.has(crew, id)
		local left = if have then CrewRules.hospitalLeft(crew, id, now) else 0
		table.insert(rows, {
			id = id,
			name = def.Name,
			icon = def.Icon,
			role = def.Role,
			ability = def.Ability,
			carry = CrewRules.carryText(id),
			have = have,
			pick = crew.pick == id,
			state = if not have then "locked" elseif left > 0 then "hospital" else "ready",
			left = math.ceil(left),
			price = CrewRules.dischargePrice(left),
		})
	end
	return rows
end

function CrewRules.clock(seconds: number): string
	local s = math.max(0, math.ceil(if seconds == seconds then seconds else 0))
	return string.format("%d:%02d", s // 60, s % 60)
end

return CrewRules
