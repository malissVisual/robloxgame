-- 8.0 SANDBOX, the collection's rules (shared/CollectionRules.luau, Config.Collection; design/sandbox/KONTRAKT.md): the
-- tiers (one each, in order, every number rising with the rarity, selling worth about a quarter of an hour on show), a
-- piece's rarity (its def's own, else by its value's thresholds; 8.3 economy: the house's ordinary furniture common …
-- rare), the income a minute and the sell price by tier and condition, broken pieces (no income, scrap), an unknown item,
-- the sample haul's totals (a first house on 12 stands earns $20 – 60 a minute; selling all of it pays 12 – 20 minutes
-- of that), a legendary piece clearly special, standsFor, the
-- view for the client, and the save: clean (garbage never trusted), fromSave (the migration: only a real save with the
-- flag; running it twice gives the same), fitStands (8.3: with a fits check) and the uids.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local FurnitureLooks = require("./FurnitureLooks")
local Rules = require("./CollectionRules")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end
local function same(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not same(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local C = Config.Collection
local Items = FurnitureLooks.Items

-- ── The tiers ─────────────────────────────────────────────────────────────
do
	check("five tiers, common first", #C.Order == 5 and C.Order[1] == "common" and C.Order[5] == "legendary", table.concat(C.Order, ","))
	local bad = {}
	local last: any = nil
	for rank, id in C.Order do
		local tier = C.Tiers[id]
		if not tier or tier.rank ~= rank or type(tier.name) ~= "string" or #tier.color ~= 3 then
			table.insert(bad, id .. ": shape")
			continue
		end
		for _, c in tier.color do
			if c < 0 or c > 255 then
				table.insert(bad, id .. ": colour")
			end
		end
		if last and not (tier.min > last.min and tier.income > last.income and tier.sell > last.sell) then
			table.insert(bad, id .. ": not above the tier before")
		end
		local minutes = tier.sell / tier.income
		if minutes < 12 or minutes > 18 then
			table.insert(bad, `{id}: sells for {minutes} minutes of income`)
		end
		last = tier
	end
	local count = 0
	for _ in C.Tiers do
		count += 1
	end
	check("each tier: a name, a colour, its rank, min / income / sell rising, selling worth 12 – 18 minutes on show (8.3 economy)", #bad == 0 and count == 5, table.concat(bad, "; "))
	check("the numbers: broken as the moves' own, scrap, the stock cap, 12 stands, a 10 s tick", C.BrokenAt == Config.Moving.Damage.BrokenAt and C.Scrap > 0 and C.Scrap < C.Tiers.common.sell and C.MaxStock == 300 and C.Stands == 12 and C.Tick == 10)
	check("legendary is clearly special (≥ 1.5 × epic's income, more than its sell, at least twice its value)", C.Tiers.legendary.income >= 1.5 * C.Tiers.epic.income
		and C.Tiers.legendary.sell > C.Tiers.epic.sell and C.Tiers.legendary.min >= 2 * C.Tiers.epic.min)
	check("the rate limit", (Config.Robust.Limits :: any).Collection == 6)
end

-- ── Rarity ────────────────────────────────────────────────────────────────
do
	local function by(value: number): string
		return Rules.rarityOf({ value = value })
	end
	local U, R, E, L = C.Tiers.uncommon.min, C.Tiers.rare.min, C.Tiers.epic.min, C.Tiers.legendary.min
	check(`by value (Config's mins): 0 / {U - 1} common, {U} uncommon, {R} rare, {E} epic, {L}+ legendary`,
		by(0) == "common" and by(U - 1) == "common" and by(U) == "uncommon" and by(R - 1) == "uncommon" and by(R) == "rare"
			and by(E - 1) == "rare" and by(E) == "epic" and by(L - 1) == "epic" and by(L) == "legendary" and by(1e6) == "legendary")
	check("8.3 economy: the mins (uncommon $100, rare $800, epic $1,500, legendary $3,000)", U == 100 and R == 800 and E == 1500 and L == 3000)
	check("its own rarity wins (a collectible)", Rules.rarityOf({ value = 50, rarity = "legendary" } :: any) == "legendary" and Rules.rarityOf({ value = 5000, rarity = "common" } :: any) == "common")
	check("an unknown own rarity: by value", Rules.rarityOf({ value = R, rarity = "mythic" } :: any) == "rare" and Rules.rarityOf({ value = R, rarity = 5 } :: any) == "rare")
	check("no def, a NaN value: common", Rules.rarityOf(nil) == "common" and Rules.rarityOf({ value = 0 / 0 }) == "common")
	local catalogue = { -- (8.3 economy: the sofa, the fridge and the record player uncommon, the clock and the piano rare)
		dining_chair = "common", toolbox = "common", dining_table = "uncommon", bicycle = "uncommon", sofa = "uncommon",
		fridge = "uncommon", record_player = "uncommon", grandfather_clock = "rare", piano = "rare",
	}
	local bad = {}
	for id, want in catalogue do
		local got = Rules.rarityOf(Rules.defOf(id))
		if got ~= want then
			table.insert(bad, `{id} {got}`)
		end
	end
	check("the catalogue's pieces (chair common … piano rare)", #bad == 0, table.concat(bad, ", "))
	-- 8.3 economy: rare is rare: the house's ordinary furniture is common, uncommon or rare; epic and legendary are only
	-- the collectibles' own rarity (Walt's farm's pieces are not the sandbox's)
	local farm: { [string]: boolean } = {}
	for _, id in (FurnitureLooks :: any).FarmPieces or {} do
		farm[id] = true
	end
	local high = {}
	for _, id in FurnitureLooks.Order do
		local def = Items[id]
		if not farm[id] and (def :: any).rarity == nil and C.Tiers[Rules.rarityOf(def)].rank > C.Tiers.rare.rank then
			table.insert(high, `{id} {Rules.rarityOf(def)}`)
		end
	end
	check("8.3 economy: the house's ordinary furniture is common … rare (epic and legendary: the collectibles only)", #high == 0, table.concat(high, ", "))
	check("tierOf / tier", Rules.tierOf({ item = "piano" }) == C.Tiers.rare and Rules.tier("rare") == C.Tiers.rare and Rules.tier("nope") == C.Tiers.common)
	local every = true
	for _, id in FurnitureLooks.Order do
		if not C.Tiers[Rules.rarityOf(Items[id])] then
			every = false
		end
	end
	check("every catalogue piece has a tier", every)
end

-- ── Income and the sell price ─────────────────────────────────────────────
do
	local sofa = { item = "sofa", condition = 1 } -- uncommon (8.3 economy), $350
	local sofaTier = C.Tiers.uncommon
	local sofaRate = 350 * sofaTier.income
	check(`income: value × the tier's rate (sofa ${sofaRate} a minute)`, near(Rules.income(sofa), sofaRate) and Rules.rarityOf(Items.sofa) == "uncommon")
	check("income × condition (half: half)", near(Rules.income({ item = "sofa", condition = 0.5 }), sofaRate / 2))
	check("sell: value × the tier's sell, whole dollars (the sofa, at 1 and at 0.5)", Rules.sell(sofa) == math.floor(350 * sofaTier.sell + 0.5)
		and Rules.sell({ item = "sofa", condition = 0.5 }) == math.floor(350 * sofaTier.sell * 0.5 + 0.5))
	local rows = {
		{ "dining_chair", "common" },
		{ "dining_table", "uncommon" },
		{ "piano", "rare" },
		{ "jukebox", "epic" },
		{ "oil_painting", "legendary" },
	}
	local bad = {}
	for _, row in rows do
		local entry = { item = row[1], condition = 0.8 }
		local tier = C.Tiers[row[2]]
		local value = Items[row[1]].value
		if Rules.rarityOf(Items[row[1]]) ~= row[2] or not near(Rules.income(entry), value * tier.income * 0.8) or Rules.sell(entry) ~= math.max(1, math.floor(value * tier.sell * 0.8 + 0.5)) then
			table.insert(bad, row[1])
		end
	end
	check("each tier's own rates (at condition 0.8)", #bad == 0, table.concat(bad, ", "))
	local piano = Rules.income({ item = "piano", condition = 1 })
	check("a rarer piece earns more of its value", piano / 1200 > Rules.income(sofa) / 350 and Rules.income(sofa) / 350 > Rules.income({ item = "dining_chair", condition = 1 }) / 40)
	check("a condition out of range is clamped (1.5 → 1, -1 / NaN → broken)", near(Rules.income({ item = "sofa", condition = 1.5 }), sofaRate) and Rules.income({ item = "sofa", condition = -1 }) == 0 and Rules.income({ item = "sofa", condition = 0 / 0 }) == 0)
end

-- ── Broken pieces ─────────────────────────────────────────────────────────
do
	local at = C.BrokenAt
	check("broken at BrokenAt and under, whole just over it", Rules.broken({ condition = at }) and Rules.broken({ condition = 0 }) and not Rules.broken({ condition = at + 0.01 }))
	check("a broken piece earns nothing on show", Rules.income({ item = "piano", condition = at }) == 0 and Rules.income({ item = "piano", condition = 0 }) == 0)
	check("… and sells for scrap (a broken piano $18, a broken TV $5: 8.3 economy, Scrap 1.5 %)", Rules.sell({ item = "piano", condition = 0.1 }) == math.floor(1200 * C.Scrap + 0.5)
		and Rules.sell({ item = "tv", condition = 0 }) == math.floor(300 * C.Scrap + 0.5) and Rules.sell({ item = "piano", condition = 0.1 }) == 18 and Rules.sell({ item = "tv", condition = 0 }) == 5)
	check("scrap is at least $1 (a broken laundry basket)", Rules.sell({ item = "laundry_basket", condition = 0 }) == 1)
	check("scrap pays less than the piece whole at its worst (the piano, and any tier's)", Rules.sell({ item = "piano", condition = 0 }) < Rules.sell({ item = "piano", condition = at + 0.01 })
		and C.Scrap < C.Tiers.common.sell * (at + 0.01))
	check("an unknown item: $0, sells for $1, common", Rules.valueOf({ item = "gone" }) == 0 and Rules.income({ item = "gone", condition = 1 }) == 0 and Rules.sell({ item = "gone", condition = 1 }) == 1 and Rules.tierOf({ item = "gone" }) == C.Tiers.common)
end

-- ── The sample haul (a first house: 21 pieces, about $6,000, a broken TV) ─
do
	local haul = {
		{ "sofa", 0.85 }, { "tv", 0.1 }, { "coffee_table", 1 }, { "grandfather_clock", 0.95 }, { "record_player", 0.9 },
		{ "fridge", 0.92 }, { "dining_table", 0.95 }, { "dining_chair", 1 }, { "dining_chair", 0.6 }, { "bed", 0.88 },
		{ "nightstand", 0.9 }, { "wardrobe", 0.9 }, { "kids_bed", 1 }, { "rocking_horse", 0.75 }, { "washing_machine", 0.9 },
		{ "toolbox", 1 }, { "bicycle", 0.8 }, { "coat_rack", 1 }, { "photo_album", 1 }, { "edelweiss_frame", 0.7 },
		{ "ski_bundle", 0.95 },
	}
	local entries: { Rules.Entry } = {}
	for index, row in haul do
		table.insert(entries, { uid = `1-{index}`, item = row[1], variant = 1, condition = row[2], name = Items[row[1]].name, got = 0 })
	end
	-- the best 12 go on show (8.3: the Big Warehouse's 12 stands, today's)
	local order = table.clone(entries)
	table.sort(order, function(a, b)
		return Rules.income(a) > Rules.income(b)
	end)
	-- 8.3: a new player's Garage shows the best 2 (8.3 economy: about $10 a minute, a third of what the haul's best 12 earn)
	local garage = Rules.standsFor(nil)
	local first = Rules.income(order[1]) + Rules.income(order[2])
	print(`      8.3: a Garage's {garage} stands show the haul's best two: ${math.floor(first * 10 + 0.5) / 10} a minute`)
	check("8.3: a new player's Garage: 2 stands, the haul's best two earn $5 – 20 a minute (8.3 economy)", garage == 2 and first >= 5 and first <= 20, first)
	for stand = 1, Rules.standsFor({ sandboxUpgrades = { warehouse = 3 } }) do
		order[stand].stand = stand
	end
	local t = Rules.totals(entries)
	print(`      the sample haul: {t.count} pieces worth ${t.value}, {t.shown} on show earn ${math.floor(t.income * 10 + 0.5) / 10} a minute, all sold ${t.sell} ({math.floor(t.sell / t.income * 10 + 0.5) / 10} minutes of showing)`)
	check("its totals: 21 pieces, $6,035, 12 on show", t.count == 21 and t.value == 6035 and t.shown == 12, `{t.count} {t.value} {t.shown}`)
	check("on 12 stands it earns $20 – 60 a minute (8.3 economy: saving up)", t.income >= 20 and t.income <= 60, t.income)
	check("selling all of it pays 12 – 20 minutes of that", t.sell / t.income >= 12 and t.sell / t.income <= 20, t.sell / t.income)
	check("the exact sums (8.3 economy: $29.06 a minute, $533 sold)", near(t.income, 29.064, 0.001) and t.sell == 533, `{t.income} {t.sell}`)
	check("the broken TV adds no income, only scrap", Rules.income(entries[2]) == 0 and Rules.sell(entries[2]) == math.floor(300 * C.Scrap + 0.5))
	-- a legendary piece is clearly special: at its tier's lowest value it out-earns the haul's three best together
	local def = { value = C.Tiers.legendary.min }
	local legendary = def.value * C.Tiers[Rules.rarityOf(def)].income
	check("a legendary at its lowest value out-earns the haul's three best pieces together", legendary > Rules.income(order[1]) + Rules.income(order[2]) + Rules.income(order[3]), legendary)
end

-- ── standsFor ─────────────────────────────────────────────────────────────
-- (8.3: with Config.Warehouse.Levels, the player's warehouse level's: tests/upgrades_test.luau; without them, as before)
do
	local C2: any = Config
	local before = C2.Warehouse
	C2.Warehouse = nil
	check("no Config.Warehouse: Config.Collection.Stands (12)", Rules.standsFor(nil) == 12 and Rules.standsFor({}) == 12)
	C2.Warehouse = { Stands = 16 }
	check("Config.Warehouse.Stands (16)", Rules.standsFor({}) == 16)
	C2.Warehouse = { Stands = 13.7 }
	check("a fraction: whole stands (13)", Rules.standsFor(nil) == 13)
	local garbage = true
	for _, bad in { 0, -3, "x", 0 / 0, math.huge } do
		C2.Warehouse = { Stands = bad }
		if Rules.standsFor(nil) ~= 12 then
			garbage = false
		end
	end
	C2.Warehouse = "nope"
	check("garbage (0, -3, a string, NaN, inf, no table): 12", garbage and Rules.standsFor(nil) == 12)
	C2.Warehouse = before
end

-- ── The view (what the client gets) ───────────────────────────────────────
do
	local entry: Rules.Entry = { uid = "7-1", item = "piano", variant = 2, condition = 0.9, name = "Grandpa's Piano", stand = 3, got = 123 }
	local v = Rules.view(entry)
	check("the entry's fields", v.uid == "7-1" and v.item == "piano" and v.variant == 2 and v.condition == 0.9 and v.name == "Grandpa's Piano" and v.stand == 3 and v.got == 123)
	check("+ rarity, value, income (cents), price, broken", v.rarity == "rare" and v.value == 1200 and v.income == math.floor(Rules.income(entry) * 100 + 0.5) / 100
		and v.income == 8.64 and v.price == Rules.sell(entry) and v.broken == false, `{v.income} {v.price}`)
	check("a copy (the entry unchanged)", (entry :: any).rarity == nil)
	check("totals of nothing", same(Rules.totals({}), { count = 0, shown = 0, value = 0, income = 0, sell = 0 }))
end

-- ── The save ──────────────────────────────────────────────────────────────
do
	check("empty", same(Rules.empty(), { entries = {}, nextUid = 1 }))
	check("uids: <userId>-<n>", Rules.uid(12345, 7) == "12345-7" and Rules.uid(-1, 2) == "-1-2")
	local garbage = true
	for _, raw in { nil, 5, "x", true, { entries = "x" }, { entries = 5, nextUid = "y" }, { nextUid = 0 / 0 } } do
		if not same(Rules.clean(raw), Rules.empty()) then
			garbage = false
		end
	end
	check("garbage: the empty one", garbage)
	local raw = {
		entries = {
			1,
			"junk",
			{},
			{ uid = 5, item = "sofa" },
			{ uid = "9-1", item = "sofa", condition = 2, stand = 1, variant = 3.7, name = "My Sofa", got = 100 },
			{ uid = "9-1", item = "tv" }, -- a uid seen already
			{ uid = "9-2", item = "tv", stand = 1, condition = 0 / 0 }, -- stand 1 is taken
			{ uid = "9-10", item = "piano", stand = 2.5, variant = -4, name = string.rep("x", 80), got = -50 },
			{ uid = "9-4", item = "gone_piece", stand = 0 },
			{ uid = "9-5", item = "fridge", stand = 501 },
			{ uid = string.rep("u", 41), item = "sofa" },
			{ uid = "9-6", item = 7 },
		},
		nextUid = 4,
	}
	local c = Rules.clean(raw)
	local e = c.entries
	check("bad pieces dropped (no uid, no item, a uid seen, too long)", #e == 5, #e)
	check("a good piece kept, mended (condition ≤ 1, a whole variant)", e[1].uid == "9-1" and e[1].item == "sofa" and e[1].condition == 1 and e[1].variant == 3 and e[1].stand == 1 and e[1].name == "My Sofa" and e[1].got == 100)
	check("a second piece on a stand: back to the stock; NaN condition: 0", e[2].uid == "9-2" and e[2].stand == nil and e[2].condition == 0)
	check("a stand not whole: the stock; a bad variant 1; a long name the def's; got ≥ 0", e[3].stand == nil and e[3].variant == 1 and e[3].name == "Upright Piano" and e[3].got == 0)
	check("an item that left the catalogue is kept (its id as the name); stand 0 / 501: the stock", e[4].item == "gone_piece" and e[4].name == "gone_piece" and e[4].stand == nil and e[5].stand == nil)
	check("nextUid past every uid (9-10 → 11)", c.nextUid == 11, c.nextUid)
	local big = { entries = {}, nextUid = 1 }
	for n = 1, C.MaxStock + 20 do
		table.insert(big.entries, { uid = `1-{n}`, item = "box", condition = 1 })
	end
	local capped = Rules.clean(big)
	check("MaxStock pieces at most (the first ones)", #capped.entries == C.MaxStock and capped.entries[C.MaxStock].uid == `1-{C.MaxStock}`)
	-- fromSave: the migration
	local good = { entries = { { uid = "9-1", item = "sofa", variant = 1, condition = 0.5, name = "Sofa", stand = 2, got = 5 } }, nextUid = 2 }
	check("a new player (nil): empty", same(Rules.fromSave(nil), Rules.empty()))
	check("a lock-only record (no money), even with a flag and a collection: empty", same(Rules.fromSave({ lock = {}, collectionKept = true, collection = good }), Rules.empty()))
	check("a save from before 8.0 (money, no flag): empty", same(Rules.fromSave({ money = 500, xp = 10 }), Rules.empty()))
	check("… a stray collection without the flag is not read", same(Rules.fromSave({ money = 500, collection = good }), Rules.empty()))
	check("a save with the flag: its collection (cleaned)", same(Rules.fromSave({ money = 500, collectionKept = true, collection = good }), good))
	check("the flag's name", Rules.SaveFlag == "collectionKept")
	local once = Rules.fromSave({ money = 1, collectionKept = true, collection = raw })
	local twice = Rules.fromSave({ money = 1, collectionKept = true, collection = once })
	check("running it twice gives the same", same(once, twice))
	check("an old save twice: still empty", same(Rules.fromSave({ money = 1, collection = Rules.fromSave({ money = 1 }) }), Rules.empty()))
	-- fitStands
	local fit: Rules.Saved = { entries = {
		{ uid = "1-1", item = "sofa", variant = 1, condition = 1, name = "Sofa", stand = 3, got = 0 },
		{ uid = "1-2", item = "sofa", variant = 1, condition = 1, name = "Sofa", stand = 12, got = 0 },
		{ uid = "1-3", item = "sofa", variant = 1, condition = 1, name = "Sofa", stand = 13, got = 0 },
		{ uid = "1-4", item = "sofa", variant = 1, condition = 1, name = "Sofa", stand = 40, got = 0 },
		{ uid = "1-5", item = "sofa", variant = 1, condition = 1, name = "Sofa", got = 0 },
	}, nextUid = 6 }
	local moved = Rules.fitStands(fit, 12)
	check("fitStands: the pieces past the stands back to the stock", moved == 2 and fit.entries[1].stand == 3 and fit.entries[2].stand == 12 and fit.entries[3].stand == nil and fit.entries[4].stand == nil)
	check("… and again: none", Rules.fitStands(fit, 12) == 0)
	-- 8.3: with fits(stand, item) (a warehouse level down: a small stand where a big one stood), a piece too big for
	-- its stand goes back too; one that fits stays
	local small = { entries = {
		{ uid = "1-1", item = "hay_wagon", variant = 1, condition = 1, name = "Hay Wagon", stand = 13, got = 1 },
		{ uid = "1-2", item = "radio", variant = 1, condition = 1, name = "Radio", stand = 14, got = 2 },
		{ uid = "1-3", item = "radio", variant = 1, condition = 1, name = "Radio", stand = 2, got = 3 },
	}, nextUid = 4 }
	local function fits(stand: number, item: string): boolean
		return not (stand > 12 and item == "hay_wagon")
	end
	check("8.3: fitStands with fits: a piece too big for its stand back to the stock too, the others stay",
		Rules.fitStands(small, 20, fits) == 1 and small.entries[1].stand == nil and small.entries[2].stand == 14 and small.entries[3].stand == 2
		and Rules.fitStands(small, 20, fits) == 0)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
