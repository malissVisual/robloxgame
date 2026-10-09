--!strict
-- 6.14, the REGULARS (the owner: "a bit MORE grind, but a FUN grind"): every business that gives you jobs remembers
-- you. The businesses are the job pictures' (shared/JobThumbs.luau Assets: Luigi's Pizza, the City Clinic, the
-- Military Base …: 25), the tiers Config.Regulars'. Pure (no Roblox): server/Regulars.luau counts and pays with it,
-- server/SpecialOrders.luau picks a REGULAR'S ORDER's business with it, client/RegularsApp.luau draws it (the phone's
-- REGULARS app, the job lists' badges), tests/regulars_test.luau checks it.
--
--   Regulars.Tiers                     Config.Regulars.Tiers, the lowest first (Bronze 5 +5 %, Silver 15 +10 %, Gold
--                                      40 +15 %, Platinum 100 +20 %)
--   Regulars.ids()                     every business's id (JobThumbs.Assets), by name
--   Regulars.nameOf(id), emojiOf(id)   the business's own name and the emoji of what it sends
--   Regulars.businessOf(info)          the business a delivery counts for (an offer, a job payload, one of its orders, a
--                                      board row: JobThumbs.assetFor), nil for a mission or a job without a picture
--   Regulars.tierOf(count)             the tier held at `count` deliveries (nil below the first) and its index (0)
--   Regulars.bonusOf(count)            its pay bonus (0.1 = +10 %), 0 without a tier
--   Regulars.nextOf(count)             the next tier and the deliveries still to go (nil, 0 at the top)
--   Regulars.progress(count)           0 … 1 from the tier held (or none) to the next one (1 at the top)
--   Regulars.percent(bonus)            0.1 → 10 (the words' "+10%")
--   Regulars.clean(raw)                a saved table checked: known ids, whole counts 1 … Config.Regulars.Cap
--   Regulars.add(regulars, id, n?)     counts n (1) more deliveries for `id`: the count before and after and the tier
--                                      reached now (nil when no new tier)
--   Regulars.badge(regulars, info)     a job row's badge: its words ("🥈 SILVER REGULAR +10%", "🤝 3/5 TO BRONZE")
--                                      and its tier's id ("" before the first tier); nil for a business never met
--   Regulars.view(regulars)            the REGULARS app: every business, met or not, with its count, tier, bonus, the
--                                      next tier and the progress to it, sorted (the highest tier, the most deliveries,
--                                      then by name; the ones never met last, by name), and the totals
--   Regulars.tierUpText(id, tier)      "Luigi's Pizza: you're a SILVER regular · +10% pay"
--   Regulars.infoOf(id)                a job info whose picture is `id` (JobThumbs.forJob: client/JobThumbUi.luau draws
--                                      the business's picture with it): its ordinary business, its special, the round
--   Regulars.ordinaryOf(id)            the Config.Jobs.Businesses ids whose picture is `id` (a REGULAR'S ORDER comes
--                                      from one of them), {} for a workplace without board deliveries (the school …)
--   Regulars.orderable(regulars)       the businesses a REGULAR'S ORDER may come from: at Config.Regulars.Order.Tier or
--                                      better, with an ordinary delivery (ordinaryOf), by name
-- The counts here are descriptive: the server decides the pay and the counts (server/Regulars.luau).

local Config = require(script.Parent.Config)
local JobThumbs = require(script.Parent.JobThumbs)

local Regulars = {}

export type Tier = Config.RegularTier

-- One business in the REGULARS app.
export type Card = {
	id: string,
	name: string,
	emoji: string,
	count: number,
	met: boolean, -- delivered for them at least once
	rank: number, -- the tier's index (0: none)
	tier: string?, -- its id, name, medal and bonus
	tierName: string?,
	icon: string?,
	bonus: number,
	nextName: string?, -- the next tier, at how many deliveries, how many to go (nil, nil, 0 at the top)
	nextAt: number?,
	toGo: number,
	progress: number, -- 0 … 1 to the next tier (1 at the top)
}

export type View = { list: { Card }, met: number, total: number, tiers: { [string]: number } }

Regulars.Tiers = Config.Regulars.Tiers

-- Every business, by its name.
local IDS: { string } = {}
for id in JobThumbs.Assets do
	table.insert(IDS, id)
end
table.sort(IDS, function(a: string, b: string): boolean
	return JobThumbs.Assets[a].name < JobThumbs.Assets[b].name
end)

function Regulars.ids(): { string }
	return table.clone(IDS)
end

function Regulars.nameOf(id: string): string
	local asset = JobThumbs.Assets[id]
	return if asset then asset.name else id
end

function Regulars.emojiOf(id: string): string
	local asset = JobThumbs.Assets[id]
	return if asset then asset.emoji else "📦"
end

-- The business a delivery counts for: its picture's (the tutorial's letters: the Post Office; the round: The Daily
-- Undead; a special: its workplace; an ordinary delivery: its business). Never a mission's.
function Regulars.businessOf(info: any): string?
	if type(info) ~= "table" or info.mission then
		return nil
	end
	return JobThumbs.assetFor(info)
end

local function whole(count: any): number
	local n = tonumber(count) or 0
	if n ~= n then
		return 0
	end
	return math.clamp(math.floor(n), 0, Config.Regulars.Cap)
end

function Regulars.tierOf(count: number): (Tier?, number)
	local held: Tier? = nil
	local index = 0
	for n, tier in Regulars.Tiers do
		if count >= tier.at then
			held, index = tier, n
		end
	end
	return held, index
end

function Regulars.bonusOf(count: number): number
	local tier = Regulars.tierOf(count)
	return if tier then tier.bonus else 0
end

function Regulars.nextOf(count: number): (Tier?, number)
	local have = whole(count)
	for _, tier in Regulars.Tiers do
		if have < tier.at then
			return tier, tier.at - have
		end
	end
	return nil, 0
end

function Regulars.progress(count: number): number
	local have = whole(count)
	local _, index = Regulars.tierOf(have)
	local nextTier = Regulars.Tiers[index + 1]
	if not nextTier then
		return 1
	end
	local low = if index > 0 then Regulars.Tiers[index].at else 0
	return math.clamp((have - low) / math.max(1, nextTier.at - low), 0, 1)
end

function Regulars.percent(bonus: number): number
	return math.floor(bonus * 100 + 0.5)
end

-- A saved `regulars` checked (server/PlayerData.luau on load): only the businesses there are, whole counts from 1 up to
-- Config.Regulars.Cap. Anything else (an old save without one) is the empty table.
function Regulars.clean(raw: any): { [string]: number }
	local out: { [string]: number } = {}
	if type(raw) ~= "table" then
		return out
	end
	for id, count in raw do
		if type(id) == "string" and JobThumbs.Assets[id] ~= nil and type(count) == "number" and count == count and count >= 1 then
			out[id] = math.min(math.floor(count), Config.Regulars.Cap)
		end
	end
	return out
end

function Regulars.add(regulars: { [string]: number }, id: string, n: number?): (number, number, Tier?)
	local before = whole(regulars[id])
	if JobThumbs.Assets[id] == nil then
		return before, before, nil
	end
	local after = math.min(before + math.max(0, math.floor(n or 1)), Config.Regulars.Cap)
	if after > 0 then
		regulars[id] = after
	end
	local _, was = Regulars.tierOf(before)
	local tier, now = Regulars.tierOf(after)
	return before, after, if now > was then tier else nil
end

function Regulars.badge(regulars: any, info: any): (string?, string?)
	local id = Regulars.businessOf(info)
	local count = if id and type(regulars) == "table" then whole(regulars[id]) else 0
	if not id or count <= 0 then
		return nil, nil
	end
	local tier = Regulars.tierOf(count)
	if tier then
		return `{tier.icon} {string.upper(tier.name)} REGULAR +{Regulars.percent(tier.bonus)}%`, tier.id
	end
	local nextTier = Regulars.nextOf(count)
	if not nextTier then
		return nil, nil
	end
	return `🤝 {count}/{nextTier.at} TO {string.upper(nextTier.name)}`, ""
end

function Regulars.view(regulars: any): View
	local list: { Card } = {}
	local tiers: { [string]: number } = {}
	local met = 0
	for _, id in IDS do
		local count = if type(regulars) == "table" then whole(regulars[id]) else 0
		local tier, rank = Regulars.tierOf(count)
		local nextTier, toGo = Regulars.nextOf(count)
		if count > 0 then
			met += 1
		end
		if tier then
			tiers[tier.id] = (tiers[tier.id] or 0) + 1
		end
		table.insert(list, {
			id = id,
			name = Regulars.nameOf(id),
			emoji = Regulars.emojiOf(id),
			count = count,
			met = count > 0,
			rank = rank,
			tier = if tier then tier.id else nil,
			tierName = if tier then tier.name else nil,
			icon = if tier then tier.icon else nil,
			bonus = if tier then tier.bonus else 0,
			nextName = if nextTier then nextTier.name else nil,
			nextAt = if nextTier then nextTier.at else nil,
			toGo = toGo,
			progress = Regulars.progress(count),
		})
	end
	table.sort(list, function(a: Card, b: Card): boolean
		if a.met ~= b.met then
			return a.met
		end
		if a.rank ~= b.rank then
			return a.rank > b.rank
		end
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a.name < b.name
	end)
	return { list = list, met = met, total = #IDS, tiers = tiers }
end

function Regulars.tierUpText(id: string, tier: Tier): string
	return `{Regulars.nameOf(id)}: you're a {string.upper(tier.name)} regular · +{Regulars.percent(tier.bonus)}% pay`
end

function Regulars.infoOf(id: string): { [string]: any }
	local ordinary: string? = nil
	for business, asset in JobThumbs.Ordinary do
		if asset == id and (ordinary == nil or business < ordinary) then
			ordinary = business
		end
	end
	if ordinary then
		return { business = ordinary }
	end
	local special: string? = nil
	for jobType, asset in JobThumbs.Special do
		if asset == id and (special == nil or jobType < special) then
			special = jobType
		end
	end
	if special then
		return { special = special }
	end
	return if id == JobThumbs.Round then { round = true } else { tutorial = id == JobThumbs.Tutorial }
end

function Regulars.ordinaryOf(id: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for business, asset in JobThumbs.Ordinary do
		if asset == id then
			out[business] = true
		end
	end
	return out
end

function Regulars.orderable(regulars: any): { string }
	local out: { string } = {}
	if type(regulars) ~= "table" then
		return out
	end
	for _, id in IDS do
		local _, rank = Regulars.tierOf(whole(regulars[id]))
		if rank >= Config.Regulars.Order.Tier and next(Regulars.ordinaryOf(id)) ~= nil then
			table.insert(out, id)
		end
	end
	return out
end

return Regulars
