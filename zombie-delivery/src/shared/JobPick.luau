--!strict
-- 6.17, the JOBS app at a glance (the owner: "when I open JOBS I want to leave, it doesn't make me want to click a
-- job"; redesign B: one hero card and compact rows). Pure Luau (no Roblox API): which job the hero card shows and the
-- short words of the rows and the top bar; client/JobsView.luau draws them, tested in tests/jobpick_test.luau.
--   JobPick.blocked(offer, onDuty)       can't be taken now: locked (level, licence, slots), or during a run neither
--                                        + ADD nor + QUEUE (the same rules as client/PhoneApps.luau's old card)
--   JobPick.hero(offers, onDuty, now)    the hero: a GOLDEN ORDER on the board (the best paid one), else a REGULAR'S
--                                        ORDER, else the best-paying job you can take; its kind ("golden", "regular",
--                                        "best"), nil when nothing fits (every row locked)
--   JobPick.rows(offers, hero, onDuty)   the other rows: the special orders, the open ones (the server's order), then
--                                        the ones you can't take
--   JobPick.danger(offer)                "🚶" / "🚲" or the danger stars and their level (0 on foot or by bike)
--   JobPick.facts(offer)                 a row's line: "📍 420 · ⏱ 2:10"
--   JobPick.heroFacts(offer)             the hero's facts: { "📍 1240", "⏱ 3:30", "+2× XP" }
--   JobPick.lockShort(offer)             a locked row's button: "🔒 LV 9", "🪪 3/5", "📦 6 SLOTS" (nil: not locked)
--   JobPick.ribbon(offer)                the hero's ribbon: "★ GOLDEN ORDER ×3", "★ REGULAR'S ORDER ×1.5" (nil: none)
--   JobPick.button(offer, onDuty)        the hero's button: "TAKE GOLDEN ORDER", "TAKE JOB", "+ ADD", "+ QUEUE"
--   JobPick.medal(regulars, offer)       the tier's medal for the row's business ("🥈"; nil: no tier there)
--   JobPick.runChip(count, money, short?), nextChip(count), rushPrefix(id), more(count, hero)   the top bar's and the list's words
-- Presentation only: the server decides every job and its pay.

local Regulars = require(script.Parent.Regulars)
local LiveEvents = require(script.Parent.LiveEvents)

local JobPick = {}

export type Kind = "golden" | "regular" | "best"

local function spec(offer: any): any
	return if type(offer) == "table" and type(offer.specialOrder) == "table" then offer.specialOrder else nil
end

local function pay(offer: any): number
	return tonumber(offer.pay) or 0
end

local function clock(seconds: number): string
	local s = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function times(value: number): string
	return if value == math.floor(value) then tostring(math.floor(value)) else string.format("%.1f", value)
end

function JobPick.blocked(offer: any, onDuty: boolean): boolean
	if type(offer) ~= "table" then
		return true
	end
	local locked = offer.locked == true or offer.tooBig == true
	if onDuty then
		if offer.queue == true then
			return false -- (6.12.8: a job waiting for your car or bike may still queue)
		end
		return locked or offer.addOrder ~= true
	end
	return locked
end

-- The best of `offers` that `fits` (the highest pay; the first on a tie).
local function best(offers: { any }, fits: (any) -> boolean): any
	local found: any = nil
	for _, offer in offers do
		if type(offer) == "table" and fits(offer) and (found == nil or pay(offer) > pay(found)) then
			found = offer
		end
	end
	return found
end

function JobPick.hero(offers: { any }?, onDuty: boolean, now: number): (any, Kind?)
	if type(offers) ~= "table" then
		return nil, nil
	end
	local function live(kind: string): (any) -> boolean
		return function(offer: any): boolean
			local s = spec(offer)
			return s ~= nil and s.kind == kind and (tonumber(s.expiresAt) or 0) > now
		end
	end
	local golden = best(offers, live("golden"))
	if golden then
		return golden, "golden"
	end
	local regular = best(offers, live("regular"))
	if regular then
		return regular, "regular"
	end
	local open = best(offers, function(offer: any): boolean
		local s = spec(offer)
		return not JobPick.blocked(offer, onDuty) and not (s and (tonumber(s.expiresAt) or 0) <= now) -- (an expired one is leaving)
	end)
	if open then
		return open, "best"
	end
	return nil, nil
end

function JobPick.rows(offers: { any }?, hero: any, onDuty: boolean): { any }
	local specials: { any } = {}
	local open: { any } = {}
	local shut: { any } = {}
	for _, offer in (if type(offers) == "table" then offers else {}) :: { any } do
		if type(offer) ~= "table" or offer == hero then
			continue
		end
		table.insert(if spec(offer) then specials elseif JobPick.blocked(offer, onDuty) then shut else open, offer)
	end
	local out = specials
	table.move(open, 1, #open, #out + 1, out)
	table.move(shut, 1, #shut, #out + 1, out)
	return out
end

function JobPick.danger(offer: any): (string, number)
	if offer.mode == "foot" then
		return "🚶", 0
	elseif offer.mode == "bike" then
		return "🚲", 0
	end
	local stars = math.clamp(math.floor(tonumber(offer.stars) or 1), 1, 4)
	return string.rep("★", stars), stars
end

function JobPick.facts(offer: any): string
	return `📍 {math.floor(tonumber(offer.distance) or 0)} · ⏱ {clock(tonumber(offer.time) or 0)}`
end

function JobPick.heroFacts(offer: any): { string }
	local out = { `📍 {math.floor(tonumber(offer.distance) or 0)}`, `⏱ {clock(tonumber(offer.time) or 0)}` }
	local s = spec(offer)
	local xp = if s then tonumber(s.xp) or 1 else 1
	if xp > 1 then
		table.insert(out, `+{times(xp)}× XP`)
	end
	return out
end

function JobPick.lockShort(offer: any): string?
	local licence = if offer.locked == true and offer.lockReason == "licence" and type(offer.licence) == "table" then offer.licence else nil
	if licence then
		return `🪪 {tonumber(licence.have) or 0}/{tonumber(licence.need) or 0}`
	elseif offer.locked == true then
		return `🔒 LV {tonumber(offer.level) or 1}`
	elseif offer.tooBig == true then
		return if offer.slots then `📦 {offer.slots} SLOTS` else "🔒"
	end
	return nil
end

function JobPick.ribbon(offer: any): string?
	local s = spec(offer)
	if not s then
		return nil
	end
	return `{if s.kind == "golden" then "★ GOLDEN ORDER" else "★ REGULAR'S ORDER"} ×{times(tonumber(s.pay) or 1)}`
end

function JobPick.button(offer: any, onDuty: boolean): string
	if onDuty then
		return if offer.addOrder ~= true and offer.queue == true then "+ QUEUE" else "+ ADD"
	end
	local s = spec(offer)
	if s and s.kind == "golden" then
		return "TAKE GOLDEN ORDER"
	elseif s then
		return "TAKE REGULAR'S ORDER"
	end
	return "TAKE JOB"
end

function JobPick.medal(regulars: any, offer: any): string?
	local id = Regulars.businessOf(offer)
	local count = if id and type(regulars) == "table" then tonumber(regulars[id]) or 0 else 0
	if count <= 0 then
		return nil
	end
	local tier = Regulars.tierOf(count)
	return if tier then tier.icon else nil
end

function JobPick.runChip(count: number, money: string, short: boolean?): string
	return if short then `▶ RUN · {count} · {money}` else `▶ YOUR RUN · {count} · {money}`
end

function JobPick.nextChip(count: number): string
	return `NEXT UP · {count}`
end

-- The rush-hour chip's words before its clock ("🕑 RUSH ×1.5 · "), nil while no event pays.
function JobPick.rushPrefix(id: string?): string?
	local payOf = LiveEvents.payOf(id, false)
	local def = LiveEvents.def(id)
	if payOf <= 1 or not def then
		return nil
	end
	local word = string.match(def.name, "^(%S+)") or def.name
	return `{def.icon} {string.upper(word)} {LiveEvents.times(payOf)} · `
end

function JobPick.more(count: number, hero: boolean): string
	local noun = if count == 1 then "JOB" else "JOBS"
	return if hero then `{count} MORE {noun}` else `{count} {noun}`
end

return JobPick
