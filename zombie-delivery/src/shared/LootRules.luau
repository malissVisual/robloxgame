--!strict
-- 9.x LOOT (the owner: "like Dungeon Quest: you go into a house and you get loot there ... outlines with their own colour
-- by how rare it is, and stars by rarity, so it has value"): the loot's pure rules (Config.Loot; no Roblox at its top
-- level: tests/loot_test.luau). server/Loot.luau rolls a house's pieces with them as the house is made and puts the
-- answer on each piece's model; client/LootOutline.luau and client/LootStars.luau show it with them.
--
-- A piece's rarity is one of Config.Collection's tiers (common … legendary, ranks 1 … 5). It starts at its own
-- (CollectionRules.rarityOf: a collectible's own, uncommon … legendary; the furniture's by its value) and the contract's
-- difficulty rolls on it (Config.Loot.Difficulty): a chance to come a tier lower (Easy), a chance a roll lifts it a tier
-- and more (Most tiers at most), more rolls (the best kept), and for Nightmare a floor for the house's best piece (at
-- least one Epic or better). Normal is the rarities as before 9.x. The dice are the house's seed's and the difficulty's (each piece its
-- own, by its spot): the same house at the same difficulty always holds the same loot. Its value is its catalogue
-- value × CollectionRules.lift (Config.Loot.Lift a tier over its own, Drop a tier under), a whole number of $.
--
--   LootRules.Order                        the difficulties, the easiest first (Config.Loot.Order)
--   LootRules.difficulty(raw)              a difficulty's id: one of Order, else Config.Loot.Default (nil: "normal")
--   LootRules.rank(rarity) / tierAt(rank)  a tier's rank (1 … 5; anything else 1) / the tier of that rank (clamped)
--   LootRules.own(item, value?)            a piece's own rarity: its catalogue def's (CollectionRules.rarityOf); an item
--                                          the catalogue does not know: by `value` (Config.Collection's mins)
--   LootRules.isCollectible(item)          its def has a rarity of its own (a collectible: never under Config.Loot.Least)
--   LootRules.seedOf(seed, difficulty)     the house's dice's seed (whole, ≥ 1)
--   LootRules.rollOne(own, collectible, difficulty, seed, spot)   one piece's rarity (its own dice: seed and spot)
--   LootRules.roll(pieces, difficulty, seed)   every piece of a house ({ { spot, item, value? } }, in the plan's order)
--                                          → { [spot] = Roll }: its rarity, its stars, its value ($), its own rarity;
--                                          then the difficulty's Floor (the best piece lifted to it when none reached it)
--   LootRules.valueOf(base, own, rarity)   $ a piece of catalogue value `base` is worth at `rarity` (CollectionRules.lift)
--   10.x danger: LootRules.lift(roll, steps, floor?)   a roll lifted `steps` tiers (a locked room's piece) and at least to
--                                          `floor` (a vault's piece: "epic", "legendary"), never past Legendary: a new Roll,
--                                          its value at the new rarity (the roll's `base`, its catalogue value)
--   LootRules.attributes(rarity, value)    what a piece's model carries: { Rarity, Stars, Value }
-- What the client shows (client/LootOutline.luau, client/LootStars.luau):
--   LootRules.color(rarity)                its tier's { r, g, b } (Config.Collection.Tiers; anything else Common's)
--   LootRules.outlined(rarity)             does it wear an outline (Config.Loot.Outline.Common: a Common too)
--   LootRules.stars(rarity)                "★★★" (its rank's stars); tierName(rarity) "RARE" (its tier's name in caps)
--   LootRules.money(amount)                "$1,450"
--   LootRules.label(rarity, value, near)   the bubble's words: "★★★" far, "★★★ RARE · $450" near (info: "RARE · $450")
--   LootRules.toastText(rarity, name, value)   "+ RARE Grandma's Clock ★★★ $450"
--   LootRules.toasted(rarity)              does picking it up or loading it toast (Config.Loot.Toast.From or rarer)
--   LootRules.sparkles(rarity)             an Epic or Legendary piece: a sparkle and a sound the first time it is seen
--   LootRules.sound(rarity)                that sound: { name, volume, pitch } (Config.Loot.Sparkle.Sounds), nil none
--   LootRules.fade(distance, reach?)       the bubble's transparency at that many studs (0 … 1: from Stars.Fade to
--                                          Stars.Range, both × reach: a phone's shorter reach, DeviceBudget.range(1))
--                                          and whether it is near (Stars.Near)

local Config = require(script.Parent.Config)
local CollectionRules = require(script.Parent.CollectionRules)

local LootRules = {}

export type Piece = { spot: number, item: string, value: number? }
export type Roll = { rarity: string, stars: number, value: number, own: string, base: number? } -- (10.x danger: base, its catalogue value)

local function tune()
	return Config.Loot
end

local function tiers()
	return Config.Collection
end

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

LootRules.Order = tune().Order

-- ── Difficulty and tiers ───────────────────────────────────────────────────

function LootRules.difficulty(raw: any): string
	if type(raw) == "string" and tune().Difficulty[raw] ~= nil then
		return raw
	end
	return tune().Default
end

function LootRules.rank(rarity: any): number
	local tier = if type(rarity) == "string" then tiers().Tiers[rarity] else nil
	return if tier then tier.rank else 1
end

function LootRules.tierAt(rank: number): string
	local order = tiers().Order
	local at = math.clamp(math.floor(if finite(rank) then rank else 1), 1, #order)
	for _, id in order do
		if tiers().Tiers[id].rank == at then
			return id
		end
	end
	return order[1]
end

function LootRules.own(item: string, value: number?): string
	local def = CollectionRules.defOf(item)
	if def then
		return CollectionRules.rarityOf(def)
	end
	return CollectionRules.rarityOf({ value = if finite(value) then value :: number else 0 })
end

function LootRules.isCollectible(item: string): boolean
	local def = CollectionRules.defOf(item)
	return def ~= nil and type((def :: any).rarity) == "string"
end

-- ── The dice ───────────────────────────────────────────────────────────────

-- 32-bit multiply, exact in doubles (in 16-bit halves).
local function mul32(a: number, b: number): number
	local hi, lo = a // 65536, a % 65536
	return ((hi * b) % 65536 * 65536 + lo * b) % 4294967296
end

-- A 32-bit hash (lowbias32): neighbouring seeds give unrelated dice.
local function hash(x: number): number
	x = bit32.bxor(x, bit32.rshift(x, 16))
	x = mul32(x, 0x7feb352d)
	x = bit32.bxor(x, bit32.rshift(x, 15))
	x = mul32(x, 0x846ca68b)
	return bit32.bxor(x, bit32.rshift(x, 16))
end

-- The dice (Park-Miller after the hash: exact in doubles, the same on every server).
local function dice(seed: number): () -> number
	local state = hash(math.floor(math.abs(seed)) % 4294967296) % 2147483646 + 1
	return function(): number
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
end

-- (10.4: LootRules.luck(rolled, chance, seed) lifts a few pieces a tier: the upgrade tree's Keen eye, by its own dice)
function LootRules.seedOf(seed: any, difficulty: any): number
	local base = if finite(seed) then math.floor(math.abs(seed)) % 4294967296 else 0
	local index = table.find(LootRules.Order, LootRules.difficulty(difficulty)) or 0
	return hash((base + tune().Salt + index * 104729) % 4294967296) + 1
end

-- One piece's rarity at `difficulty`: its own dice (the house's seed and its spot), so a piece's loot never depends on
-- the others'.
function LootRules.rollOne(own: string, collectible: boolean, difficulty: any, seed: number, spot: number): string
	local rule = tune().Difficulty[LootRules.difficulty(difficulty)]
	local start = LootRules.rank(own)
	local least = if collectible then LootRules.rank(tune().Least) else 1
	local top = #tiers().Order
	local roll = dice(LootRules.seedOf(seed, difficulty) + (if finite(spot) then math.floor(math.abs(spot)) else 0) * 7919)
	for _ = 1, 3 do
		roll() -- (warm the dice: a spot's neighbour starts apart)
	end
	if rule.Down > 0 and roll() < rule.Down then
		return LootRules.tierAt(math.max(math.min(least, start), start - 1))
	end
	local best = 0
	for _ = 1, math.max(1, math.floor(rule.Rolls)) do
		local steps = 0
		local most = math.max(1, math.floor(rule.Most))
		if rule.Up > 0 and roll() < rule.Up then
			steps = 1
			while steps < most and start + steps < top and roll() < rule.Again do
				steps += 1
			end
		end
		best = math.max(best, steps)
	end
	return LootRules.tierAt(math.min(top, start + best))
end

function LootRules.valueOf(base: number, own: string, rarity: string): number
	local value = if finite(base) then math.max(0, base) else 0
	local lift = CollectionRules.lift(own, rarity)
	return if lift == 1 then value else math.floor(value * lift + 0.5)
end

function LootRules.roll(pieces: { Piece }, difficulty: any, seed: number): { [number]: Roll }
	local out: { [number]: Roll } = {}
	local bases: { [number]: number } = {}
	local best: Piece? = nil
	for _, piece in pieces do
		local def = CollectionRules.defOf(piece.item)
		local base = if finite(piece.value) then math.max(0, piece.value :: number) elseif def and finite(def.value) then math.max(0, def.value) else 0
		local own = LootRules.own(piece.item, base)
		local rarity = LootRules.rollOne(own, LootRules.isCollectible(piece.item), difficulty, seed, piece.spot)
		bases[piece.spot] = base
		out[piece.spot] = { rarity = rarity, stars = LootRules.rank(rarity), value = LootRules.valueOf(base, own, rarity), own = own, base = base }
		local now = out[piece.spot]
		local was = if best then out[best.spot] else nil
		if was == nil or now.stars > was.stars or (now.stars == was.stars and now.value > was.value) then
			best = piece
		end
	end
	-- the difficulty's floor: the house's best piece comes at least so rare
	local floor = tune().Difficulty[LootRules.difficulty(difficulty)].Floor
	local chosen = best
	if floor and chosen and out[chosen.spot].stars < LootRules.rank(floor) then
		local got = out[chosen.spot]
		got.rarity = LootRules.tierAt(LootRules.rank(floor))
		got.stars = LootRules.rank(got.rarity)
		got.value = LootRules.valueOf(bases[chosen.spot], got.own, got.rarity)
	end
	return out
end

-- 10.x danger: a roll lifted `steps` tiers and at least to `floor`, never past Legendary (a new roll; the same one when
-- nothing changes). Its value from its catalogue value (`base`; an older roll without one: its value back at its own).
function LootRules.lift(roll: Roll, steps: number, floor: string?): Roll
	local top = #tiers().Order
	local rank = LootRules.rank(roll.rarity)
	local want = math.min(top, rank + math.max(0, math.floor(if finite(steps) then steps else 0)))
	if floor then
		want = math.max(want, LootRules.rank(floor))
	end
	if want <= rank then
		return roll
	end
	local rarity = LootRules.tierAt(want)
	local base = roll.base
	if base == nil then
		local lift = CollectionRules.lift(roll.own, roll.rarity)
		base = if lift > 0 then roll.value / lift else roll.value
	end
	return { rarity = rarity, stars = LootRules.rank(rarity), value = LootRules.valueOf(base :: number, roll.own, rarity), own = roll.own, base = base }
end

-- 10.4: the run host's upgrade tree's Keen eye: each piece of a house's rolls a `chance` (0 … 0.25) of a tier more, by
-- its own die (the house's seed and its spot: the same house, the same luck), never past the top. → the spots lifted.
function LootRules.luck(rolled: { [number]: Roll }, chance: number, seed: number): { number }
	local lifted: { number } = {}
	local p = if finite(chance) then math.clamp(chance, 0, 0.25) else 0
	if p <= 0 then
		return lifted
	end
	local spots: { number } = {}
	for spot in rolled do
		table.insert(spots, spot)
	end
	table.sort(spots)
	for _, spot in spots do
		local roll = dice((if finite(seed) then math.floor(math.abs(seed)) else 0) * 31 + spot * 7919 + 104723)
		roll()
		if roll() < p then
			local was = rolled[spot]
			local now = LootRules.lift(was, 1)
			if now ~= was then
				rolled[spot] = now
				table.insert(lifted, spot)
			end
		end
	end
	return lifted
end

function LootRules.attributes(rarity: string, value: number): { [string]: any }
	local id = if type(rarity) == "string" and tiers().Tiers[rarity] then rarity else tiers().Order[1]
	return { Rarity = id, Stars = LootRules.rank(id), Value = if finite(value) then math.max(0, math.floor(value + 0.5)) else 0 }
end

-- ── What the client shows ──────────────────────────────────────────────────

function LootRules.color(rarity: any): { number }
	local tier = if type(rarity) == "string" then tiers().Tiers[rarity] else nil
	return (tier or tiers().Tiers[tiers().Order[1]]).color
end

function LootRules.outlined(rarity: any): boolean
	return LootRules.rank(rarity) > 1 or tune().Outline.Common == true
end

function LootRules.stars(rarity: any): string
	return string.rep("★", LootRules.rank(rarity))
end

function LootRules.money(amount: number): string
	local text = tostring(math.floor((if finite(amount) then math.max(0, amount) else 0) + 0.5))
	while true do
		local swapped
		text, swapped = string.gsub(text, "^(%d+)(%d%d%d)", "%1,%2")
		if swapped == 0 then
			break
		end
	end
	return "$" .. text
end

function LootRules.tierName(rarity: any): string
	local tier = if type(rarity) == "string" then tiers().Tiers[rarity] else nil
	return string.upper((tier or tiers().Tiers[tiers().Order[1]]).name)
end
local nameOf = LootRules.tierName

function LootRules.info(rarity: any, value: number): string
	return `{nameOf(rarity)} · {LootRules.money(value)}`
end

function LootRules.label(rarity: any, value: number, near: boolean): string
	if not near then
		return LootRules.stars(rarity)
	end
	return `{LootRules.stars(rarity)} {LootRules.info(rarity, value)}`
end

function LootRules.toastText(rarity: any, name: string, value: number): string
	return `+ {nameOf(rarity)} {name} {LootRules.stars(rarity)} {LootRules.money(value)}`
end

function LootRules.toasted(rarity: any): boolean
	return LootRules.rank(rarity) >= LootRules.rank(tune().Toast.From)
end

function LootRules.sparkles(rarity: any): boolean
	return LootRules.rank(rarity) >= LootRules.rank("epic")
end

function LootRules.sound(rarity: any): { any }?
	local id = if type(rarity) == "string" then rarity else ""
	local sound = tune().Sparkle.Sounds[id]
	return if type(sound) == "table" and type(sound[1]) == "string" then sound else nil
end

function LootRules.fade(distance: number, reach: number?): (number, boolean)
	local S = tune().Stars
	local k = if finite(reach) and (reach :: number) > 0 then reach :: number else 1
	local d = if finite(distance) then math.max(0, distance) else math.huge
	local alpha = if d == math.huge then 1 else math.clamp((d - S.Fade * k) / math.max((S.Range - S.Fade) * k, 1e-3), 0, 1)
	return alpha, d <= S.Near
end

return LootRules
