-- 9.x LOOT (the owner: "like Dungeon Quest: you go into a house and you get loot there ... outlines with their own colour
-- by how rare it is, and stars by rarity, so it has value"): the pure rules in the standalone Luau CLI.
--   * Config.Loot's numbers (the difficulties, the lift, the client's looks within their bounds; the supply crates' six
--     still there for the city); the sounds are the sheets' own (no new audio).
--   * A rarity for every piece (shared/LootRules.luau): Normal is the rarities as before 9.x (the furniture's by its
--     value, a collectible's own), a collectible never under Uncommon, nothing past Common or Legendary, the same house
--     and difficulty always the same dice, each piece its own (its spot), the value by the lift.
--   * The odds over many seeds of real layouts (HouseLayout.plan): Nightmare better than Insane better than Hard better
--     than Normal better than Easy (the haul's mean rank, its value, its income), Nightmare always one Epic or better.
--   * The outlines' pick (shared/OutlinePick.luau loot): the shared budget with the enemies (never past 31 − Spare), the
--     rarest first, then the nearest, the range, the hold (no swap, no blink), Commons none (or with Common, theirs).
--   * The stars' and the toast's words, the fade, which tiers toast and sparkle.
--   * The rest of the game sees the same rarity and value (shared/CollectionRules.luau Entry.rarity): the stock's view,
--     the price and the income, the save (kept, junk dropped, none reads as its own), the book's page (its rarest
--     found), the trade's value, the auction's lot, the leaderboard's legendaries, the legendary badge.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local LootRules = require("./LootRules")
local OutlinePick = require("./OutlinePick")
local CollectionRules = require("./CollectionRules")
local BookRules = require("./CollectionBookRules")
local HouseLayout = require("./HouseLayout")
local SoundSheet = require("./SoundSheet")
local AuctionRules = require("./AuctionRules")
local PlayerTradeRules = require("./PlayerTradeRules")
local SandboxLeadersRules = require("./SandboxLeadersRules")
local SandboxBadgeRules = require("./SandboxBadgeRules")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local L = Config.Loot
local TIERS = Config.Collection.Order

-- ── The numbers ────────────────────────────────────────────────────────────
do
	check("the difficulties: easy, normal, hard, insane, nightmare (the lobby's), Normal by default", table.concat(L.Order, ",") == "easy,normal,hard,insane,nightmare" and L.Default == "normal")
	local every = true
	for _, id in L.Order do
		local d = L.Difficulty[id]
		every = every and d ~= nil and d.Down >= 0 and d.Down < 1 and d.Up >= 0 and d.Up < 1 and d.Again >= 0 and d.Again < 1 and d.Rolls >= 1 and d.Most >= 1
	end
	check("each difficulty: its chances 0 … 1, a roll at least, a tier at least", every)
	local n = L.Difficulty.normal
	check("Normal is the rarities as before (no tier down, no tier up, no floor)", n.Down == 0 and n.Up == 0 and n.Floor == nil)
	check("Easy: a little worse (a chance of a tier down, none up)", L.Difficulty.easy.Down > 0 and L.Difficulty.easy.Down <= 0.25 and L.Difficulty.easy.Up == 0)
	check("Hard, Insane, Nightmare: a chance up, more each", L.Difficulty.hard.Up > 0 and L.Difficulty.insane.Up >= L.Difficulty.hard.Up and L.Difficulty.nightmare.Up >= L.Difficulty.insane.Up
		and L.Difficulty.nightmare.Rolls >= L.Difficulty.insane.Rolls and L.Difficulty.insane.Rolls >= L.Difficulty.hard.Rolls)
	check("Nightmare: at least one Epic or better a house", L.Difficulty.nightmare.Floor == "epic")
	check("the lift: a tier up worth more, a tier down less", L.Lift > 1 and L.Lift <= 2 and L.Drop < 1 and L.Drop >= 0.5)
	check("a collectible never under Uncommon", L.Least == "uncommon")
	check("the tag a word", type(L.Tag) == "string" and #L.Tag > 0)
	check("the city's supply crates keep their six numbers (server/Items.luau)", L.Count == 16 and L.Respawn == 40 and L.MoneyMin == 25 and L.MoneyMax == 90 and L.ItemChance == 0.4 and L.Reach == 9)
	local O = L.Outline
	check("the outlines: a soft fill (0.85 … 0.9), a clear edge, within the budget, a few times a second", O.Fill >= 0.85 and O.Fill <= 0.9 and O.Edge >= 0 and O.Edge <= 0.3
		and O.Count >= 4 and O.Count <= OutlinePick.BUDGET and O.Every >= 0.1 and O.Every <= 0.5 and O.HoldRange > 1 and O.HoldRange < 1.5 and O.Range >= 30)
	local S = L.Stars
	check("the stars: sized like Danny's bubble, a few, faded before their reach, the near words within it", S.Text >= 11 and S.Text <= 16 and S.Detail >= 10 and S.Detail <= S.Text
		and S.Tall >= 18 and S.Tall <= Config.MoveHelper.Bubble.Tall and S.Count >= 3 and S.Count <= 12 and S.Fade < S.Range and S.Near < S.Fade and S.Every >= 0.1 and S.Every <= 0.5)
	check("a phone still shows a few stars and outlines", math.floor(S.Count * Config.Performance.Lite.Count + 0.5) >= 3 and math.floor(O.Count * Config.Performance.Lite.Count + 0.5) >= 4)
	check("the toast: from a tier, a gap, a few at once, within the HUD's column", Config.Collection.Tiers[L.Toast.From] ~= nil and L.Toast.Gap >= 0.3 and L.Toast.Most >= 1 and L.Toast.Most <= 3
		and L.Toast.Width <= 352 and L.Toast.Seconds >= 1.5 and L.Toast.Seconds <= 4)
	local sheets = { SoundSheet.Sfx, SoundSheet.Sfx2, SoundSheet.Sfx3, SoundSheet.Sfx4, SoundSheet.Sfx5 }
	local function known(name: string): boolean
		for _, sheet in sheets do
			if sheet[name] then
				return true
			end
		end
		return false
	end
	local sounds = true
	for _, rarity in { "epic", "legendary" } do
		local sound = LootRules.sound(rarity)
		sounds = sounds and sound ~= nil and known(sound[1]) and sound[2] > 0 and sound[2] <= 1 and sound[3] > 0.5 and sound[3] < 2
	end
	check("Epic and Legendary: a sound of the sheets each (no new audio), a common none", sounds and LootRules.sound("common") == nil and LootRules.sound("rare") == nil)
	check("Epic's and Legendary's sounds differ", LootRules.sound("epic")[1] ~= LootRules.sound("legendary")[1])
end

-- ── Difficulty and tiers ───────────────────────────────────────────────────
do
	check("difficulty: a known one as it is, nil or junk Normal", LootRules.difficulty("hard") == "hard" and LootRules.difficulty(nil) == "normal" and LootRules.difficulty("brutal") == "normal" and LootRules.difficulty(5) == "normal")
	check("ranks: common 1 … legendary 5, junk 1", LootRules.rank("common") == 1 and LootRules.rank("rare") == 3 and LootRules.rank("legendary") == 5 and LootRules.rank("gold") == 1 and LootRules.rank(nil) == 1)
	check("tierAt: by rank, clamped", LootRules.tierAt(3) == "rare" and LootRules.tierAt(0) == "common" and LootRules.tierAt(9) == "legendary")
	check("own: the catalogue's (the piano rare, a chair common, an epic collectible epic)", LootRules.own("piano") == "rare" and LootRules.own("dining_chair") == "common" and LootRules.own("antique_vase") == "epic")
	check("own: a piece the catalogue does not know, by its value", LootRules.own("nope", 500) == "uncommon" and LootRules.own("nope", 5000) == "legendary" and LootRules.own("nope") == "common")
	check("a collectible is one (its def's own rarity), a sofa is not", LootRules.isCollectible("oil_painting") and not LootRules.isCollectible("sofa"))
end

-- ── One piece's dice ───────────────────────────────────────────────────────
do
	local same, normal, bounds, least = true, true, true, true
	local moved = 0
	for seed = 1, 400 do
		for spot = 1, 6 do
			for _, d in L.Order do
				for _, own in TIERS do
					local a = LootRules.rollOne(own, own ~= "common", d, seed, spot)
					local b = LootRules.rollOne(own, own ~= "common", d, seed, spot)
					same = same and a == b
					bounds = bounds and Config.Collection.Tiers[a] ~= nil
					if own ~= "common" then
						least = least and LootRules.rank(a) >= LootRules.rank(L.Least)
					end
					if d == "normal" then
						normal = normal and a == own
					end
					if d == "hard" and a ~= own then
						moved += 1
					end
				end
			end
		end
	end
	check("the same house, spot and difficulty: the same rarity every time", same)
	check("Normal: every piece its own rarity", normal)
	check("every rarity a tier (never under Common, never past Legendary)", bounds)
	check("a collectible never under Uncommon (Easy's tier down stops there)", least)
	check("Hard lifts some", moved > 0)
	local differ = 0
	for seed = 1, 200 do
		if LootRules.rollOne("uncommon", false, "nightmare", seed, 1) ~= LootRules.rollOne("uncommon", false, "nightmare", seed, 2) then
			differ += 1
		end
	end
	check("each spot its own dice (two spots of one house differ now and then)", differ > 10 and differ < 190, differ)
	check("Hard lifts a tier at most (Most 1)", (function(): boolean
		for seed = 1, 3000 do
			if LootRules.rank(LootRules.rollOne("common", false, "hard", seed, 3)) > 2 then
				return false
			end
		end
		return true
	end)())
	check("the value: a tier up × Lift, two × Lift², a tier down × Drop, its own as it is (whole $)",
		LootRules.valueOf(1000, "rare", "epic") == math.floor(1000 * L.Lift + 0.5) and LootRules.valueOf(1000, "rare", "legendary") == math.floor(1000 * L.Lift ^ 2 + 0.5)
		and LootRules.valueOf(1000, "rare", "uncommon") == math.floor(1000 * L.Drop + 0.5) and LootRules.valueOf(1000, "rare", "rare") == 1000 and LootRules.valueOf(-5, "rare", "epic") == 0)
	local a = LootRules.attributes("rare", 449.6)
	check("a model's attributes: Rarity, Stars, Value (whole $); junk: Common", a.Rarity == "rare" and a.Stars == 3 and a.Value == 450 and LootRules.attributes("gold", 10).Rarity == "common" and LootRules.attributes("gold", 10).Stars == 1)
end

-- ── A house: the odds over many seeds of real layouts ──────────────────────
do
	local houses: { { seed: number, pieces: { LootRules.Piece } } } = {}
	for _, kind in { "house", "big", "cabin", "lodge", "mill", "cottage" } do
		for seed = 1, 2 do
			local plan = HouseLayout.plan(seed * 7 + 1, kind)
			local pieces: { LootRules.Piece } = {}
			for _, spot in plan.spots do
				table.insert(pieces, { spot = spot.id, item = spot.item })
			end
			table.insert(houses, { seed = seed * 7 + 1, pieces = pieces })
		end
	end
	type Sum = { rank: number, value: number, base: number, income: number, income0: number, pieces: number, epicHouses: number, houses: number, lowest: number }
	local sums: { [string]: Sum } = {}
	local normalSame = true
	local consistent = true
	for _, d in L.Order do
		local sum: Sum = { rank = 0, value = 0, base = 0, income = 0, income0 = 0, pieces = 0, epicHouses = 0, houses = 0, lowest = math.huge }
		for rep = 0, 59 do
			for _, house in houses do
				local seed = house.seed + rep * 7919
				local out = LootRules.roll(house.pieces, d, seed)
				local epic = 0
				for _, piece in house.pieces do
					local r = out[piece.spot]
					local def = CollectionRules.defOf(piece.item)
					local base = if def then def.value else 0
					sum.rank += r.stars
					sum.value += r.value
					sum.base += base
					sum.income += r.value * CollectionRules.tier(r.rarity).income
					sum.income0 += base * CollectionRules.tier(r.own).income
					sum.pieces += 1
					if r.stars >= 4 then
						epic += 1
					end
					if d == "normal" then
						normalSame = normalSame and r.rarity == CollectionRules.rarityOf(def) and r.value == base
					end
					-- the stock's value of such a piece is the roll's (CollectionRules.valueOf with its rarity)
					consistent = consistent and CollectionRules.valueOf({ item = piece.item, rarity = r.rarity } :: any) == r.value and r.stars == LootRules.rank(r.rarity)
				end
				sum.houses += 1
				sum.lowest = math.min(sum.lowest, epic)
				if epic > 0 then
					sum.epicHouses += 1
				end
			end
		end
		sums[d] = sum
	end
	check("Normal: every piece of every house its own rarity and its catalogue value (as before 9.x)", normalSame)
	check("a roll's value is the stock's (CollectionRules.valueOf with its rarity), its stars its rank", consistent)
	local function mean(d: string): number
		return sums[d].rank / sums[d].pieces
	end
	local order = true
	for index = 2, #L.Order do
		local lo, hi = sums[L.Order[index - 1]], sums[L.Order[index]]
		order = order and mean(L.Order[index]) > mean(L.Order[index - 1]) and hi.value > lo.value and hi.income > lo.income
	end
	check(`the odds over {sums.normal.houses} houses: Easy < Normal < Hard < Insane < Nightmare (mean stars, value, income)`, order,
		string.format("%.3f %.3f %.3f %.3f %.3f", mean("easy"), mean("normal"), mean("hard"), mean("insane"), mean("nightmare")))
	check("Easy a little worse than Normal (its income ×0.85 … 1)", sums.easy.income / sums.normal.income >= 0.85 and sums.easy.income < sums.normal.income, sums.easy.income / sums.normal.income)
	check("Nightmare clearly better (its income ×1.3 … 2.2 of Normal's)", sums.nightmare.income / sums.normal.income >= 1.3 and sums.nightmare.income / sums.normal.income <= 2.2, sums.nightmare.income / sums.normal.income)
	check("Nightmare: every house holds an Epic or better", sums.nightmare.lowest >= 1 and sums.nightmare.epicHouses == sums.nightmare.houses, sums.nightmare.lowest)
	check("Normal: not every house does (the floor is Nightmare's)", sums.normal.epicHouses < sums.normal.houses)
	check("more houses with an Epic or better the harder it is", sums.hard.epicHouses >= sums.normal.epicHouses and sums.insane.epicHouses > sums.hard.epicHouses and sums.nightmare.epicHouses >= sums.insane.epicHouses)

	-- the floor lifts the best piece only, and only when it is needed
	local plain: { LootRules.Piece } = { { spot = 1, item = "dining_chair" }, { spot = 2, item = "sofa" }, { spot = 3, item = "piano" } }
	local floorOk = true
	for seed = 1, 300 do
		local out = LootRules.roll(plain, "nightmare", seed)
		local best = math.max(out[1].stars, out[2].stars, out[3].stars)
		floorOk = floorOk and best >= 4
	end
	check("Nightmare on a house of plain pieces: still an Epic or better every time (its best piece lifted)", floorOk)
	local same = true
	for seed = 1, 50 do
		local a, b = LootRules.roll(plain, "hard", seed), LootRules.roll(plain, "hard", seed)
		for spot = 1, 3 do
			same = same and a[spot].rarity == b[spot].rarity and a[spot].value == b[spot].value
		end
	end
	check("a house rolled again (the same seed and difficulty): the same loot", same)
	local alone = LootRules.roll({ plain[2] }, "insane", 77)[2]
	check("a piece's loot is its own (alone or with the others: the same, but for the floor)", alone.rarity == LootRules.roll(plain, "insane", 77)[2].rarity)
	local given = LootRules.roll({ { spot = 4, item = "nope", value = 500 } }, "normal", 1)[4]
	check("a value given (the move's own) is the base", given.value == 500 and given.rarity == "uncommon")
end

-- ── The outlines: the shared budget, the pick ──────────────────────────────
do
	local B = OutlinePick.BUDGET
	check("the budget: Roblox's 31 less the spare", B == OutlinePick.ROBLOX_MAX - Config.Outline.Spare and B > 0)
	local fits = true
	for enemies = 0, 40 do
		local room = OutlinePick.room(enemies, L.Outline.Count)
		fits = fits and room >= 0 and room <= L.Outline.Count and math.min(enemies, OutlinePick.limit) + room <= B
	end
	check("the enemies outlined + the loot's room never pass 31 − Spare (any number of enemies)", fits)
	check("room: none left once the enemies take the budget, all of it with none", OutlinePick.room(B, 20) == 0 and OutlinePick.room(B + 5, 20) == 0 and OutlinePick.room(0, 20) == math.min(20, B) and OutlinePick.room(20, 20) == B - 20)
	local function entries(list: { { number } }): { OutlinePick.LootEntry }
		local out: { OutlinePick.LootEntry } = {}
		for _, e in list do
			table.insert(out, { distance = e[1], rank = e[2], outlined = e[3] == 1 })
		end
		return out
	end
	local function picked(chosen: { [number]: boolean }): string
		local list: { number } = {}
		for index in chosen do
			table.insert(list, index)
		end
		table.sort(list)
		return table.concat(list, ",")
	end
	local E1 = entries({ { 10, 2 }, { 40, 5 }, { 5, 1 }, { 20, 3 }, { 15, 3 }, { 70, 5 } })
	check("the rarest first, then the nearest; a Common none; out of range none", picked(OutlinePick.loot(E1, 3, 60, 0)) == "2,4,5", picked(OutlinePick.loot(E1, 3, 60, 0)))
	check("… the count is the most", picked(OutlinePick.loot(E1, 1, 60, 0)) == "2")
	check("… the enemies take their share first", picked(OutlinePick.loot(E1, 20, 60, B - 2)) == "2,5" and picked(OutlinePick.loot(E1, 20, 60, B)) == "")
	local many: { OutlinePick.LootEntry } = {}
	for index = 1, 60 do
		table.insert(many, { distance = index, rank = 2 + index % 4, outlined = false })
	end
	local most = 0
	for _ in OutlinePick.loot(many, 99, 1000, 0) do
		most += 1
	end
	check("never more than the budget, whatever the count asked", most == B, most)
	-- the hold: one outlined keeps it a little farther and a little ahead of its tier
	local held = entries({ { 30, 3, 1 }, { 28, 3 } })
	check("hysteresis: the outlined one keeps its outline over one a little nearer of its tier", picked(OutlinePick.loot(held, 1, 60, 0)) == "1")
	local fresh = entries({ { 30, 3 }, { 28, 3 } })
	check("… without one outlined, the nearer gets it", picked(OutlinePick.loot(fresh, 1, 60, 0)) == "2")
	local edge = entries({ { 65, 4, 1 }, { 65, 4 } })
	check("… one outlined keeps it past the range (HoldRange), a new one there gets none", picked(OutlinePick.loot(edge, 5, 60, 0)) == "1")
	check("… a rarer one still comes first (the priority)", picked(OutlinePick.loot(entries({ { 10, 3, 1 }, { 50, 4 } }), 1, 60, 0)) == "2")
	local was = L.Outline.Common
	L.Outline.Common = true
	check("Common true: a Common wears one too (the faint grey-white)", picked(OutlinePick.loot(entries({ { 5, 1 } }), 5, 60, 0)) == "1" and LootRules.outlined("common"))
	L.Outline.Common = was
	check("Common false (the default): a Common wears none, an Uncommon does", not LootRules.outlined("common") and LootRules.outlined("uncommon"))
end

-- ── The stars' and the toast's words ───────────────────────────────────────
do
	check("stars: ★ × the rank", LootRules.stars("common") == "★" and LootRules.stars("rare") == "★★★" and LootRules.stars("legendary") == "★★★★★" and LootRules.stars("junk") == "★")
	check("the bubble far: the stars only", LootRules.label("rare", 450, false) == "★★★")
	check("the bubble near: the stars, the tier, the value", LootRules.label("rare", 450, true) == "★★★ RARE · $450" and LootRules.info("legendary", 6000) == "LEGENDARY · $6,000")
	check("the toast: \"+ RARE Grandma's Clock ★★★ $450\"", LootRules.toastText("rare", "Grandma's Clock", 450) == "+ RARE Grandma's Clock ★★★ $450")
	check("money: thousands with commas, whole dollars", LootRules.money(1234567) == "$1,234,567" and LootRules.money(999.6) == "$1,000" and LootRules.money(-3) == "$0")
	check("the tier's colour (Config.Collection's), junk Common's", LootRules.color("epic") == Config.Collection.Tiers.epic.color and LootRules.color("x") == Config.Collection.Tiers.common.color)
	local S = L.Stars
	local a0, n0 = LootRules.fade(S.Near - 1)
	local a1 = LootRules.fade(S.Fade)
	local a2 = LootRules.fade((S.Fade + S.Range) / 2)
	local a3, n3 = LootRules.fade(S.Range)
	check("the fade: drawn up to Fade, half way at the middle, gone at Range; near within Near", a0 == 0 and n0 and a1 == 0 and math.abs(a2 - 0.5) < 1e-6 and a3 == 1 and not n3 and LootRules.fade(math.huge) == 1)
	local k = Config.Performance.Lite.Range
	check("… a phone's shorter reach: the same fade within it (Fade and Range × its reach), near as near", LootRules.fade(S.Fade * k, k) == 0 and LootRules.fade(S.Range * k, k) == 1
		and math.abs(LootRules.fade((S.Fade + S.Range) / 2 * k, k) - 0.5) < 1e-6 and select(2, LootRules.fade(S.Near - 1, k)) == true)
	check("the toast's words as big as the HUD's own toasts (14 px at the column's scale)", L.Toast.Text >= 14)
	check("toasts: from Toast.From (Uncommon) up, a Common none", LootRules.toasted("uncommon") and LootRules.toasted("legendary") and not LootRules.toasted("common"))
	check("the first sight's sparkle: Epic and Legendary only", LootRules.sparkles("epic") and LootRules.sparkles("legendary") and not LootRules.sparkles("rare"))
end

-- ── The rest of the game: the same rarity and value ────────────────────────
do
	local plain = { uid = "1-1", item = "sofa", variant = 1, condition = 1, name = "Sofa", got = 0 }
	local lifted = { uid = "1-2", item = "sofa", variant = 1, condition = 1, name = "Sofa", got = 0, rarity = "epic" }
	check("a piece without a rarity (a save from before 9.x) is its item's own", CollectionRules.pieceRarity(plain :: any) == "uncommon" and CollectionRules.valueOf(plain :: any) == 350)
	check("a piece with one: its own roll, its value lifted (two tiers: × Lift²)", CollectionRules.pieceRarity(lifted :: any) == "epic" and CollectionRules.valueOf(lifted :: any) == math.floor(350 * L.Lift ^ 2 + 0.5)
		and CollectionRules.tierOf(lifted :: any).rank == 4)
	check("junk is its own", CollectionRules.pieceRarity({ item = "sofa", rarity = "shiny" } :: any) == "uncommon" and CollectionRules.valueOf({ item = "sofa", rarity = 7 } :: any) == 350)
	local v = CollectionRules.view(lifted :: any)
	check("the stock's view: its rarity and value; the income and the price at its tier", v.rarity == "epic" and v.value == CollectionRules.valueOf(lifted :: any)
		and math.abs(v.income - math.floor(v.value * Config.Collection.Tiers.epic.income * 100 + 0.5) / 100) < 1e-9 and v.price == math.max(1, math.floor(v.value * Config.Collection.Tiers.epic.sell + 0.5)))
	check("… so it earns and sells for more than its plain twin", CollectionRules.income(lifted :: any) > CollectionRules.income(plain :: any) and CollectionRules.sell(lifted :: any) > CollectionRules.sell(plain :: any))
	check("keepRarity: another tier kept, its own and junk none", CollectionRules.keepRarity("sofa", "epic") == "epic" and CollectionRules.keepRarity("sofa", "uncommon") == nil and CollectionRules.keepRarity("sofa", "gold") == nil)
	local saved = CollectionRules.clean({ entries = { lifted, plain, { uid = "1-3", item = "piano", condition = 1, rarity = "rare" }, { uid = "1-4", item = "piano", condition = 1, rarity = "nope" } }, nextUid = 5 })
	check("the save: a rarity kept, its own and junk dropped (they read as their own)", saved.entries[1].rarity == "epic" and saved.entries[2].rarity == nil and saved.entries[3].rarity == nil and saved.entries[4].rarity == nil
		and CollectionRules.pieceRarity(saved.entries[3]) == "rare")
	local again = CollectionRules.clean(saved)
	check("… cleaned again: the same", again.entries[1].rarity == "epic" and #again.entries == 4)
	check("the trades: the piece's value is the game's price at its rarity", PlayerTradeRules.value(lifted :: any) == CollectionRules.sell(lifted :: any) and PlayerTradeRules.value(lifted :: any) > PlayerTradeRules.value(plain :: any))
	local lot = AuctionRules.lotOf(lifted :: any, 1, "Ann", nil, 1)
	check("the auction: a lot's rarity and worth are the piece's", lot.rarity == "epic" and lot.worth == CollectionRules.valueOf(lifted :: any))
	check("… an Uncommon sofa rolled Epic may be consigned, its plain twin not", AuctionRules.consignable(lifted :: any) and not AuctionRules.consignable(plain :: any))
	check("the leaderboard: a piece rolled Legendary is one", SandboxLeadersRules.isLegendary({ item = "sofa", rarity = "legendary" } :: any) and not SandboxLeadersRules.isLegendary(plain :: any))
	check("the legendary badge: its own roll counts, else its item's", #SandboxBadgeRules.fromAdded("sofa", "legendary") == 1 and #SandboxBadgeRules.fromAdded("sofa", nil) == 0
		and #SandboxBadgeRules.fromAdded("oil_painting", nil) == 1 and #SandboxBadgeRules.fromAdded("oil_painting", "epic") == 0)

	-- the book's page: its rarest found
	local book = BookRules.empty()
	BookRules.record(book, "sofa", 0.9)
	check("the book: a page as before (no top: its item's own)", book.sofa.top == nil and BookRules.pageRarity("sofa", book.sofa) == "uncommon" and BookRules.pageValue("sofa", book.sofa) == 350)
	BookRules.record(book, "sofa", 0.5, nil, "epic")
	check("… one rarer came home: the page's top, its value at it", book.sofa.top == "epic" and BookRules.pageRarity("sofa", book.sofa) == "epic" and BookRules.pageValue("sofa", book.sofa) == CollectionRules.valueOf(lifted :: any) and book.sofa.n == 2)
	BookRules.record(book, "sofa", 1, nil, "rare")
	BookRules.record(book, "sofa", 1, nil, "common")
	check("… a plainer one keeps the rarest", book.sofa.top == "epic" and book.sofa.best == 1 and book.sofa.n == 4)
	BookRules.record(book, "piano", 1, nil, "legendary")
	check("… counts: a page found Legendary counts as a legendary", BookRules.counts(book).legendary == 1)
	local view = BookRules.view(book)
	local clean = BookRules.clean({ sofa = { n = 2, best = 1, top = "epic" }, piano = { n = 1, best = 1, top = "common" }, tv = { n = 1, best = 1, top = "gold" } })
	check("… the remote's view carries it, the save keeps a rarer one only", view.sofa.top == "epic" and clean.sofa.top == "epic" and clean.piano.top == nil and clean.tv.top == nil)
	local filled = BookRules.backfill({ lifted, plain })
	check("… an older save's book from the stock keeps its rarest", filled.sofa.top == "epic" and filled.sofa.n == 2)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
