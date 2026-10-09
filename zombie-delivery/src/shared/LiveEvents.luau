--!strict
-- 6.15, LIVE EVENTS: the rules and the words, pure (no Roblox API; tests/liveevents_test.luau runs it in the Luau CLI).
-- server/LiveEvents.luau runs the events, client/EventBanner.luau, client/Weather.luau and client/MapView.luau show
-- them, server/Jobs.luau and server/Zombies.luau ask what they change; Config.LiveEvents holds the numbers.
-- The state goes to every client as workspace attributes (LiveEvents.Attr): the event's id, when it started and ends
-- (server time: workspace:GetServerTimeNow), its phase, and for the supply drop and the horde their spot (the crate,
-- the gate), the drop-off, who carries the crate and the horde's progress.
--
--   LiveEvents.Attr, AttrNames                           the workspace attributes of the state (by name, all of them)
--   LiveEvents.Ids, def(id), seconds(id), color(id)      the four events, their Config entry, length and colour
--   LiveEvents.nightLeft(hour), dayLeft(hour)            seconds of night (of day) left on the game's clock
--   LiveEvents.canStart(id, hour, players)               may it start now? (false and why not)
--   LiveEvents.deck(r, last), pick(deck, can)            the events in a shuffled order; the first that can start
--   LiveEvents.gap(r, first)                             seconds from one event's start to the next one's
--   LiveEvents.payOf(id, mission)                        a job finished now pays × this (1: none, always for a mission)
--   LiveEvents.wavesOf(id, mission), roamOf(id)          the job waves' and the roamers' multipliers
--   LiveEvents.speedOf(id, speed)                        a zombie's speed during it (capped)
--   LiveEvents.extraOffers(id), refreshOf(id, seconds)   rush hour's board: more offers, sooner new ones
--   LiveEvents.clock(seconds), times(m), money(n)        "3:12", "×1.5", "$1,234"
--   LiveEvents.payLine(id), boardLine(id, left), workLine(id)   the result's line, the job board's, the phone's WORK
--   LiveEvents.boardPrefix(id)                           the board's strip before its clock
--   LiveEvents.banner(view, narrow?)                     the HUD banner's words: { title, hint, clock, count?, progress? }
--   LiveEvents.startText(id, extra?), endText(id, why)   the toasts when it starts and ends
--   LiveEvents.levelScale(level), supplyReward(level)    the rewards
--   LiveEvents.hordeShares(kills, killed, total, beaten, levelOf)   every killer's share of the horde's reward
--   LiveEvents.Sides, gates(side), hordeSpot(gate, out, lateral), bursts(count, n)   the horde's way in
--   LiveEvents.supplySpot(side, along, out), dropOff(), delivered(x, z)   the supply drop's spot and the depot's pad

local Config = require(script.Parent.Config)
local Map = require(script.Parent.Map)

local LiveEvents = {}

LiveEvents.Ids = { "bloodmoon", "rush", "supply", "horde" }

-- The workspace attributes the server keeps (nil when there is no event, or nothing of that kind).
LiveEvents.Attr = {
	Id = "LiveEvent", -- string: the running event's id
	Started = "LiveEventStarted", -- number: server time it started
	Ends = "LiveEventEnds", -- number: server time it ends
	Phase = "LiveEventPhase", -- string: supply "falling" | "ground" | "carried"; horde "coming" | "gate"
	Spot = "LiveEventSpot", -- Vector3: the crate (in the air, on the street, in somebody's hands) or the horde's gate
	Goal = "LiveEventGoal", -- Vector3: the supply drop's drop-off at the depot
	Carrier = "LiveEventCarrier", -- string: who carries the crate (display name)
	Side = "LiveEventSide", -- string: the side the horde comes from ("east")
	Done = "LiveEventDone", -- number: the horde's fallen
	Total = "LiveEventTotal", -- number: the horde's count
}
-- All of them (the server clears them at an event's end).
LiveEvents.AttrNames = {
	"LiveEvent",
	"LiveEventStarted",
	"LiveEventEnds",
	"LiveEventPhase",
	"LiveEventSpot",
	"LiveEventGoal",
	"LiveEventCarrier",
	"LiveEventSide",
	"LiveEventDone",
	"LiveEventTotal",
} :: { string }

local function tuning()
	return Config.LiveEvents
end

function LiveEvents.def(id: string?): Config.LiveEventDef?
	if type(id) ~= "string" then
		return nil
	end
	return tuning().Events[id]
end

-- The event's length in seconds (0 for an unknown id).
function LiveEvents.seconds(id: string?): number
	local def = LiveEvents.def(id)
	return if def then def.minutes * 60 else 0
end

function LiveEvents.color(id: string?): { number }
	local def = LiveEvents.def(id)
	return if def then def.color else { 220, 220, 220 }
end

-- ── The clock ──────────────────────────────────────────────────────────────

local function hoursToSeconds(hours: number): number
	return hours * Config.DayNight.DayLength / 24
end

-- Seconds of night left at this hour (0 by day). The night runs NightFrom … NightTo over midnight (Map.isNight).
function LiveEvents.nightLeft(hour: number): number
	local h = hour % 24
	local from, to = Config.DayNight.NightFrom, Config.DayNight.NightTo
	if h >= from then
		return hoursToSeconds(24 - h + to)
	elseif h < to then
		return hoursToSeconds(to - h)
	end
	return 0
end

-- Seconds of day left at this hour (0 at night).
function LiveEvents.dayLeft(hour: number): number
	local h = hour % 24
	local from, to = Config.DayNight.NightFrom, Config.DayNight.NightTo
	if h >= to and h < from then
		return hoursToSeconds(from - h)
	end
	return 0
end

-- May the event start now? The Blood Moon at night with MinNightLeft s of it to go, rush hour by day with MinDayLeft
-- s to go, the supply drop and the horde any time; none with nobody in the server. False and a reason otherwise.
function LiveEvents.canStart(id: string, hour: number, players: number): (boolean, string?)
	local t = tuning()
	if players < 1 then
		return false, "nobody is playing"
	end
	if LiveEvents.def(id) == nil then
		return false, "no such event"
	end
	if id == "bloodmoon" then
		if LiveEvents.nightLeft(hour) < t.BloodMoon.MinNightLeft then
			return false, "it needs the night"
		end
	elseif id == "rush" then
		if LiveEvents.dayLeft(hour) < t.Rush.MinDayLeft then
			return false, "it needs the day"
		end
	end
	return true, nil
end

-- ── The schedule ───────────────────────────────────────────────────────────

-- The events in a new order (r: a random number 0 … 1 each call); `last` (the one just played) never first.
function LiveEvents.deck(r: () -> number, last: string?): { string }
	local list = table.clone(tuning().Order)
	for i = #list, 2, -1 do
		local j = math.clamp(math.floor(r() * i) + 1, 1, i)
		list[i], list[j] = list[j], list[i]
	end
	if #list > 1 and list[1] == last then
		list[1], list[2] = list[2], list[1]
	end
	return list
end

-- The first event of the deck that can start now, and where it is (nil when none can).
function LiveEvents.pick(deck: { string }, can: (string) -> boolean): (string?, number?)
	for index, id in deck do
		if can(id) then
			return id, index
		end
	end
	return nil, nil
end

-- Seconds until the next event: First minutes for the first one, Every minutes from one start to the next.
function LiveEvents.gap(r: number, first: boolean): number
	local range = if first then tuning().First else tuning().Every
	local low, high = range[1], range[2] or range[1]
	return (low + (high - low) * math.clamp(r, 0, 1)) * 60
end

-- ── What an event changes ──────────────────────────────────────────────────

-- A job finished while it runs pays × this (Economy.payout's eventMultiplier); a mission never.
function LiveEvents.payOf(id: string?, mission: boolean): number
	if mission then
		return 1
	end
	if id == "bloodmoon" then
		return tuning().BloodMoon.Pay
	elseif id == "rush" then
		return tuning().Rush.Pay
	end
	return 1
end

-- The job waves' spawn multiplier (× the job's own: Jobs.dangerOf); a mission's stay as they are.
function LiveEvents.wavesOf(id: string?, mission: boolean): number
	return if id == "bloodmoon" and not mission then tuning().BloodMoon.Waves else 1
end

-- The roamers around every player without a job (× the night's: server/Zombies.luau keepRoamers).
function LiveEvents.roamOf(id: string?): number
	return if id == "bloodmoon" then tuning().BloodMoon.Roam else 1
end

-- A zombie's speed during the event: the Blood Moon's × Speed, never over MaxSpeed (a zombie faster than that already
-- keeps its own).
function LiveEvents.speedOf(id: string?, speed: number): number
	if id ~= "bloodmoon" then
		return speed
	end
	local t = tuning().BloodMoon
	return math.max(speed, math.min(speed * t.Speed, t.MaxSpeed))
end

-- Rush hour: more ordinary offers a danger level (and on foot, by bike): JobRules.roles' `extra`.
function LiveEvents.extraOffers(id: string?): number
	return if id == "rush" then tuning().Rush.ExtraOffers else 0
end

-- Rush hour: the board's new offers come at least this often.
function LiveEvents.refreshOf(id: string?, seconds: number): number
	return if id == "rush" then math.min(seconds, tuning().Rush.Refresh) else seconds
end

-- ── The words ──────────────────────────────────────────────────────────────

function LiveEvents.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds - 1e-6))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- 1234 → "$1,234" (the server's toasts)
function LiveEvents.money(n: number): string
	local text = tostring(math.max(0, math.floor(n)))
	repeat
		local made, count = string.gsub(text, "^(%d+)(%d%d%d)", "%1,%2")
		text = made
	until count == 0
	return "$" .. text
end

-- "×2", "×1.5"
function LiveEvents.times(multiplier: number): string
	local text = string.format("%.2f", multiplier)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return "×" .. text
end

local function head(id: string?): string
	local def = LiveEvents.def(id)
	return if def then `{def.icon} {def.name}` else "LIVE EVENT"
end

-- The result window's line of the event's pay ("🌕 BLOOD MOON ×2"; client/Hud.luau, the money after it).
function LiveEvents.payLine(id: string?): string
	local pay = LiveEvents.payOf(id, false)
	if pay <= 1 then
		return "Live event bonus"
	end
	return `{head(id)} {LiveEvents.times(pay)}`
end

-- The job board's strip while an event pays ("🕑 RUSH HOUR · ×1.5 pay · 3:12"), nil for the others; its words before
-- the clock (a countdown label adds the clock: client/SpecialOrderUi.luau countdown).
function LiveEvents.boardPrefix(id: string?): string?
	local pay = LiveEvents.payOf(id, false)
	if pay <= 1 then
		return nil
	end
	return `{head(id)} · {LiveEvents.times(pay)} pay · `
end

function LiveEvents.boardLine(id: string?, left: number): string?
	local prefix = LiveEvents.boardPrefix(id)
	return if prefix then prefix .. LiveEvents.clock(left) else nil
end

-- The phone's WORK tile while an event pays ("🌕 BLOOD MOON · jobs pay ×2"), nil for the others.
function LiveEvents.workLine(id: string?): string?
	local pay = LiveEvents.payOf(id, false)
	if pay <= 1 then
		return nil
	end
	return `{head(id)} · jobs pay {LiveEvents.times(pay)}`
end

function LiveEvents.hordeText(done: number, total: number): string
	return `HORDE {math.max(0, math.floor(done))}/{math.max(0, math.floor(total))}`
end

local SIDE_NAMES: { [string]: string } = { north = "the north", east = "the east", south = "the south", west = "the west" }

export type View = {
	id: string?,
	left: number, -- seconds to its end
	phase: string?,
	carrier: string?,
	side: string?,
	done: number?,
	total: number?,
}

export type Banner = {
	title: string, -- "🌕 BLOOD MOON"
	hint: string, -- one line under it
	clock: string, -- "3:12"
	count: string?, -- the horde: "HORDE 34/60"
	progress: number?, -- the horde: 0 … 1
	color: { number },
}

-- The HUD banner's words for the event as the attributes say it (nil without one); `narrow` (the narrow banner on a
-- crowded screen): the hint's first part only.
function LiveEvents.banner(view: View, narrow: boolean?): Banner?
	local def = LiveEvents.def(view.id)
	if not def then
		return nil
	end
	local hint = def.hint
	local count: string? = nil
	local progress: number? = nil
	if view.id == "supply" then
		hint = if view.phase == "falling" then "Falling · follow the light beam"
			elseif view.phase == "carried" then `{view.carrier or "Somebody"} has it · to the depot!`
			else "Grab it · bring it to the depot"
	elseif view.id == "horde" then
		local total = math.max(0, view.total or 0)
		local done = math.clamp(view.done or 0, 0, total)
		count = LiveEvents.hordeText(done, total)
		progress = if total > 0 then done / total else 0
		hint = `From {SIDE_NAMES[view.side or ""] or "outside"} · hold the gate · reward by kills`
	end
	if narrow then
		hint = string.match(hint, "^(.-) · ") or hint
	end
	return { title = `{def.icon} {def.name}`, hint = hint, clock = LiveEvents.clock(view.left), count = count, progress = progress, color = def.color }
end

-- The toast when it starts (`extra`: the horde's side, the supply's district).
function LiveEvents.startText(id: string, extra: string?): string
	local def = LiveEvents.def(id)
	if not def then
		return "A live event starts!"
	end
	local minutes = def.minutes
	if id == "bloodmoon" then
		return `{def.icon} {def.name} for {minutes} min! Jobs pay {LiveEvents.times(tuning().BloodMoon.Pay)}, the zombies come faster and in numbers.`
	elseif id == "rush" then
		return `{def.icon} {def.name} for {minutes} min! Jobs pay {LiveEvents.times(tuning().Rush.Pay)} and the board has more of them.`
	elseif id == "supply" then
		return `{def.icon} {def.name}! A crate is coming down{if extra then ` {extra}` else ""}: the first to bring it to the depot gets the reward.`
	end
	return `{def.icon} {def.name}! A horde comes from {SIDE_NAMES[extra or ""] or "outside"}: hold the gate, the reward goes by your kills.`
end

-- The toast when it ends (`why`: "time", "admin", "dawn", "dusk", "delivered", "beaten", "nobody").
function LiveEvents.endText(id: string, why: string): string
	local def = LiveEvents.def(id)
	local name = if def then def.name else "LIVE EVENT"
	if why == "dawn" then
		return `{name} is over: the sun is up.`
	elseif why == "dusk" then
		return `{name} is over: the night comes.`
	elseif why == "time" and id == "supply" then
		return "The supply drop is gone: nobody brought it in."
	elseif why == "time" and id == "horde" then
		return "The horde falls back. The reward goes by your kills."
	end
	return `{name} is over.`
end

-- ── The rewards ────────────────────────────────────────────────────────────

function LiveEvents.levelScale(level: number): number
	return 1 + tuning().LevelScale * (math.max(1, math.floor(level)) - 1)
end

local function money5(value: number): number
	return math.floor(value / 5 + 0.5) * 5
end

-- The supply drop's reward for a courier of this level: money ($5 steps), XP.
function LiveEvents.supplyReward(level: number): (number, number)
	local t = tuning().Supply
	local scale = LiveEvents.levelScale(level)
	return money5(t.Money * scale), math.floor(t.Xp * scale + 0.5)
end

export type Share = { money: number, xp: number, kills: number }

-- Every killer's share of the horde's reward: the pool (Money, Xp) whole when the horde was beaten, else the share of it
-- that fell (killed / total); split by the kills credited (`kills`: key → kills), × each one's LevelScale (levelOf).
-- Anybody with a kill gets $5 and 1 XP at least.
function LiveEvents.hordeShares<K>(kills: { [K]: number }, killed: number, total: number, beaten: boolean, levelOf: (K) -> number): { [K]: Share }
	local t = tuning().Horde
	local out: { [K]: Share } = {}
	local sum = 0
	for _, n in kills do
		if n > 0 then
			sum += n
		end
	end
	if sum <= 0 then
		return out
	end
	local pool = if beaten then 1 else math.clamp(if total > 0 then killed / total else 0, 0, 1)
	for key, n in kills do
		if n <= 0 then
			continue
		end
		local part = pool * n / sum * LiveEvents.levelScale(levelOf(key))
		out[key] = { money = math.max(5, money5(t.Money * part)), xp = math.max(1, math.floor(t.Xp * part + 0.5)), kills = n }
	end
	return out
end

-- ── The horde ──────────────────────────────────────────────────────────────

LiveEvents.Sides = { "north", "east", "south", "west" }

-- Outward from the safe zone on that side (x east, z south; north is −z on the compass).
local OUTWARD: { [string]: { number } } = { north = { 0, -1 }, east = { 1, 0 }, south = { 0, 1 }, west = { -1, 0 } }

export type Gate = { x: number, z: number, dx: number, dz: number }

-- The gates on that side: where the streets that cross the safe zone's edge leave it (the middle ones first, Gates of
-- them), Stop studs outside the edge, with the way out (dx, dz).
function LiveEvents.gates(side: string): { Gate }
	local out = OUTWARD[side]
	if not out then
		return {}
	end
	local half = Config.City.SafeHalf
	local stop = half + tuning().Horde.Stop
	local reach = half + tuning().Horde.Out[2]
	local alongX = out[1] ~= 0 -- an east or west side: the streets along X (constant z) cross it
	local sign = if alongX then out[1] else out[2]
	local found: { { along: number } } = {}
	for _, s in Map.Segments do
		local straight = if alongX then math.abs(s.az - s.bz) < 0.5 else math.abs(s.ax - s.bx) < 0.5
		local along = if alongX then s.az else s.ax
		-- (on the way out: the street's ends × the side's sign; it must run from inside the edge to the far spawns)
		local u1 = sign * (if alongX then s.ax else s.az)
		local u2 = sign * (if alongX then s.bx else s.bz)
		if straight and math.abs(along) < half - 20 and math.min(u1, u2) <= half and math.max(u1, u2) >= reach then
			table.insert(found, { along = along })
		end
	end
	table.sort(found, function(a, b)
		if math.abs(a.along) ~= math.abs(b.along) then
			return math.abs(a.along) < math.abs(b.along)
		end
		return a.along < b.along
	end)
	local gates: { Gate } = {}
	local seen: { [number]: boolean } = {}
	for _, entry in found do
		local key = math.floor(entry.along + 0.5)
		if seen[key] then
			continue
		end
		seen[key] = true
		if out[1] ~= 0 then
			table.insert(gates, { x = out[1] * stop, z = entry.along, dx = out[1], dz = 0 })
		else
			table.insert(gates, { x = entry.along, z = out[2] * stop, dx = 0, dz = out[2] })
		end
		if #gates >= tuning().Horde.Gates then
			break
		end
	end
	return gates
end

-- Where a horde zombie comes in: on the gate's street, Out studs past the edge (out 0 … 1), across the road a little
-- (lateral 0 … 1).
function LiveEvents.hordeSpot(gate: Gate, out: number, lateral: number): (number, number)
	local t = tuning().Horde
	local beyond = t.Out[1] + (t.Out[2] - t.Out[1]) * math.clamp(out, 0, 1) - t.Stop
	local across = (math.clamp(lateral, 0, 1) * 2 - 1) * (Config.City.RoadWidth / 2 - 4)
	return gate.x + gate.dx * beyond - gate.dz * across, gate.z + gate.dz * beyond + gate.dx * across
end

-- The horde's bursts: `count` split over `n` (the first ones take the odd ones).
function LiveEvents.bursts(count: number, n: number): { number }
	local list: { number } = {}
	local parts = math.max(1, math.floor(n))
	local total = math.max(0, math.floor(count))
	local each = total // parts
	local extra = total - each * parts
	for k = 1, parts do
		table.insert(list, each + (if k <= extra then 1 else 0))
	end
	return list
end

-- ── The supply drop ────────────────────────────────────────────────────────

-- A street spot for the crate from three dice (0 … 1): a side of the safe zone, a place along it and how far out
-- (Distance from the middle on the zone's square), snapped to the nearest road. Nil when that is no good: inside the
-- safe zone or within Margin of it, in the water, out of town or too far from where it was meant.
function LiveEvents.supplySpot(sideRoll: number, alongRoll: number, outRoll: number): (number?, number?)
	local t = tuning().Supply
	local side = LiveEvents.Sides[math.clamp(math.floor(sideRoll * 4) + 1, 1, 4)]
	local out = OUTWARD[side]
	local d = t.Distance[1] + (t.Distance[2] - t.Distance[1]) * math.clamp(outRoll, 0, 1)
	local along = (math.clamp(alongRoll, 0, 1) * 2 - 1) * d
	local px = if out[1] ~= 0 then out[1] * d else along
	local pz = if out[2] ~= 0 then out[2] * d else along
	local cx, cz, dx, dz, width = Map.nearestRoad(px, pz)
	-- (by the kerb, not in the middle of the traffic: the side from the third die)
	local kerb = (width / 2 - 5) * (if (outRoll * 1000) % 2 < 1 then 1 else -1)
	local x, z = cx - dz * kerb, cz + dx * kerb
	local half = Config.City.SafeHalf
	if math.max(math.abs(x), math.abs(z)) < half + t.Margin then
		return nil, nil
	end
	if Map.inWater(x, z) or (x - px) ^ 2 + (z - pz) ^ 2 > 120 ^ 2 then
		return nil, nil
	end
	local downtown = Map.Districts[1]
	if downtown then
		local x0, x1, z0, z1 = Map.districtEdges(downtown)
		if x < x0 or x > x1 or z < z0 or z > z1 then
			return nil, nil
		end
	end
	return x, z
end

-- The drop-off at the depot (x, z): DropOff from the depot's middle.
function LiveEvents.dropOff(): (number, number)
	local off = tuning().Supply.DropOff
	return Map.Depot.x + off[1], Map.Depot.z + off[2]
end

-- Is (x, z) on the drop-off (within DeliverRadius, flat)?
function LiveEvents.delivered(x: number, z: number): boolean
	local dx, dz = LiveEvents.dropOff()
	local r = tuning().Supply.DeliverRadius
	return (x - dx) ^ 2 + (z - dz) ^ 2 <= r * r
end

return LiveEvents
