-- 8.3 SANDBOX, the PAINT shop's rules (shared/VanPaintRules.luau, Config.VanPaint): the catalogue as the owner asked
-- (8 – 12 body colours, the free factory's cream first; a few liveries, the free ZDC classic first; one or two premium
-- items, Collector gold behind the collection book's "A legendary!" milestone: 8.3 economy), the prices against the economy,
-- what may be bought (known, not owned, unlocked, the money) and worn (owned), the Look a van wears (the body, the
-- stripe, "contrast", the roof's stripes on both looks' flat roof), the window's swatches, the labels inked in the
-- stripe's colour, and the save checked and migrated (only a real save written with the flag).
-- Run with tests/run_tests.py (the server's purchases: tests/vanpaint_runtime_test.luau).
local Config = require("./Config")
local Rules = require("./VanPaintRules")
local SprinterLooks = require("./SprinterLooks")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
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
local P = Config.VanPaint

-- ── The catalogue ───────────────────────────────────────────────────────────
local normal, premium = 0, 0
for _, item in Rules.Paints do
	if item.premium then
		premium += 1
	else
		normal += 1
	end
end
for _, item in Rules.Liveries do
	premium += if item.premium then 1 else 0
end
check(`8 – 12 body colours ({normal}) and one or two premium items ({premium})`, normal >= 8 and normal <= 12 and premium >= 1 and premium <= 2, `{normal} {premium}`)
check("a few liveries (3 – 6)", #Rules.Liveries >= 3 and #Rules.Liveries <= 6)
check("the factory's first: ZDC cream and ZDC classic, free for everybody", Rules.Default.paint == "cream" and Rules.Default.livery == "zdc" and Rules.free(Rules.find("cream") :: any)
	and Rules.free(Rules.find("zdc") :: any) and Rules.find("cream").name == "ZDC cream" and Rules.find("zdc").name == "ZDC classic")
check("ZDC classic is the ZDC red of the parts look (SprinterLooks.Finish.stripe)", same(Rules.look(Rules.Default).stripe, SprinterLooks.Finish.stripe.color))
check("ZDC cream is the van's Config.Cars colour (the parts look's factory paint)", (function()
	for _, def in Config.Cars do
		if def.id == Config.Sandbox.Van then
			return same(def.color, Rules.find("cream").color)
		end
	end
	return false
end)())
local ids, bad = {}, {}
for _, items in { Rules.Paints, Rules.Liveries } do
	for _, item in items do
		if ids[item.id] or #item.name == 0 or #item.name > 18 or item.price < 0 or item.price ~= math.floor(item.price) then
			table.insert(bad, item.id)
		end
		ids[item.id] = true
		if item.kind == "paint" and not (type(item.color) == "table" and #item.color == 3) then
			table.insert(bad, item.id .. " colour")
		end
		if item.kind == "livery" and not (item.stripe == "contrast" or (type(item.stripe) == "table" and #item.stripe == 3)) then
			table.insert(bad, item.id .. " stripe")
		end
		if item.roof and P.Roofs[item.roof] == nil then
			table.insert(bad, item.id .. " roof")
		end
	end
end
check("every item: a new id, a short name, a whole price, its colour (a livery: RGB or contrast), a known roof", #bad == 0, table.concat(bad, ", "))
local gold = Rules.find("gold") :: any
check("Collector gold: premium, unlocked by the book's \"A legendary!\" (8.3 economy: a paid milestone of Config.CollectionBook), $5,000", gold ~= nil and gold.premium and gold.unlock == "legendary"
	and Rules.lockText(gold) == "Collection book: A legendary!" and gold.material == "Metal" and gold.price == 5000)
local known = false
for _, milestone in Config.CollectionBook.Milestones do
	known = known or milestone.id == gold.unlock
end
check("… its milestone exists", known)
local chrome = Rules.find("chrome") :: any
check("Mirror chrome: premium, the late flex (8.3 economy: $50,000, tens of hours of a first haul's $40 – 50 a minute)", chrome ~= nil and chrome.premium and chrome.price == 50000
	and chrome.price >= 50 * 60 * 15 and chrome.unlock == nil)
local cheapest, total = math.huge, 0
for _, items in { Rules.Paints, Rules.Liveries } do
	for _, item in items do
		total += item.price
		if item.price > 0 then
			cheapest = math.min(cheapest, item.price)
		end
	end
end
check("the economy: the cheapest colour within the start money ($500), a livery within an hour of a first haul ($40 a minute)", cheapest <= Config.Sandbox.StartMoney and Rules.find("alpine").price <= 40 * 60)
check(`everything costs {Rules.money(total)} (Config's tuning line, 8.3 economy)`, total == 65700, total)
check("find: junk and unknown ids give nil", Rules.find(nil) == nil and Rules.find(5) == nil and Rules.find("") == nil and Rules.find(string.rep("x", 64)) == nil and Rules.find("purple") == nil)

-- ── Buying and wearing ──────────────────────────────────────────────────────
local saved = Rules.empty()
check("a new player's: nothing bought, the factory's worn", next(saved.owned) == nil and saved.worn.paint == "cream" and saved.worn.livery == "zdc")
check("… owns the factory's (everybody's), not the rest", Rules.owns(saved, "cream") and Rules.owns(saved, "zdc") and not Rules.owns(saved, "red") and not Rules.owns(saved, "racing"))
local ok, why, price = Rules.check(saved, "red", 500, {})
check("Fire red with $500: may be bought, $500", ok and why == nil and price == 500)
ok, why = Rules.check(saved, "red", 499, {})
check("… with $499: no, the price and your money said", not ok and why == "Fire red costs $500: you have $499.", why)
ok, why = Rules.check(saved, "purple", 1e9, {})
check("an unknown id: no", not ok and why == "That's no paint.")
ok, why = Rules.check(saved, "cream", 1e9, {})
check("an everybody's item: never bought (yours already)", not ok and string.find(why :: string, "yours already", 1, true) ~= nil)
ok, why = Rules.check(saved, "gold", 1e9, {})
check("Collector gold without the milestone: locked, says what unlocks it", not ok and why == "Collector gold unlocks with the collection book's \"A legendary!\".", why)
check("… another milestone paid (every collectible, and 8.2's retired one): still locked", not Rules.check(saved, "gold", 1e9, { collectibles24 = true, collectibles = true }))
ok = Rules.check(saved, "gold", 1e9, { legendary = true })
check("… with it paid: may be bought", ok)
ok, why = Rules.check(saved, "gold", 100, { legendary = true })
check("… but not without its money", not ok and string.find(why :: string, "$5,000", 1, true) ~= nil)
Rules.buy(saved, "red")
check("bought: owned for good and worn at once", saved.owned.red == true and saved.worn.paint == "red" and saved.worn.livery == "zdc")
ok, why = Rules.check(saved, "red", 1e9, {})
check("… never bought twice", not ok and string.find(why :: string, "yours already", 1, true) ~= nil)
Rules.buy(saved, "racing")
check("a livery bought: worn, the paint kept", saved.owned.racing and saved.worn.livery == "racing" and saved.worn.paint == "red")
ok = Rules.wear(saved, "cream")
check("wearing the cream again: free, the red still owned", ok and saved.worn.paint == "cream" and saved.owned.red)
ok, why = Rules.wear(saved, "black")
check("wearing what is not yours: no", not ok and why == "Midnight black isn't yours yet: buy it first." and saved.worn.paint == "cream")
ok, why = Rules.wear(saved, "nope")
check("… an unknown id: no", not ok and why == "That's no paint.")
check("wearing a livery leaves the paint", Rules.wear(saved, "zdc") and saved.worn.livery == "zdc" and saved.worn.paint == "cream")

-- ── The look ────────────────────────────────────────────────────────────────
local factory = Rules.look(Rules.Default)
check("the factory's look: cream, SmoothPlastic, the ZDC red band, no roof stripes", factory.factoryPaint and factory.factoryLivery and same(factory.body, { 232, 226, 210 })
	and factory.bodyMaterial == "SmoothPlastic" and factory.bodyReflectance == 0 and #factory.roof == 0)
local red = Rules.look({ paint = "red", livery = "racing" })
check("Fire red with racing stripes: a light contrast on the dark red, two roof stripes in it", same(red.body, { 176, 32, 32 }) and same(red.stripe, P.Contrast.Light) and #red.roof == 2
	and same(red.roof[1].color, P.Contrast.Light) and not red.factoryPaint and not red.factoryLivery)
local yellow = Rules.look({ paint = "yellow", livery = "racing" })
check("… on taxi yellow the dark contrast", same(yellow.stripe, P.Contrast.Dark))
local cream = Rules.look({ paint = "cream", livery = "racing" })
check("… on the cream the dark one", same(cream.stripe, P.Contrast.Dark))
local alpine = Rules.look({ paint = "forest", livery = "alpine" })
check("Alpine: its pine band, a snow-white roof panel in its own colour", same(alpine.stripe, { 34, 110, 70 }) and #alpine.roof == 1 and same(alpine.roof[1].color, P.Roofs.snow[1].color))
local goldline = Rules.look({ paint = "black", livery = "goldline" })
check("Gold line: a metal gold band, two thin roof pinstripes", goldline.stripeMaterial == "Metal" and #goldline.roof == 2 and goldline.roof[1].size[1] < 0.3)
local chromeLook = Rules.look({ paint = "chrome", livery = "zdc" })
check("Mirror chrome: Foil with a little reflectance; Collector gold: Metal", chromeLook.bodyMaterial == "Foil" and chromeLook.bodyReflectance > 0 and Rules.look({ paint = "gold" }).bodyMaterial == "Metal")
check("an unknown or junk worn: the factory's look", same(Rules.look({ paint = "x", livery = 5 }), factory) and same(Rules.look(nil), factory) and same(Rules.look({ paint = "racing", livery = "red" }), factory))

-- the roof's stripes lie on the flat high roof of both looks: the parts look's Roof piece (z, its top) and the owner's
-- Blender model's flat roof (design/blender-sprinter/sprinter.py: y -5.0 … 10.75 at HEIGHT, the sides rounded inside 3.0)
local roofPiece: any = nil
for _, piece in SprinterLooks.body() do
	if piece.name == "Roof" then
		roofPiece = piece
	end
end
local top = roofPiece.at[2] + roofPiece.size[2] / 2
local z0, z1 = roofPiece.at[3] - roofPiece.size[3] / 2, roofPiece.at[3] + roofPiece.size[3] / 2
local onRoof, bad2 = true, {}
for name in P.Roofs do
	for _, piece in Rules.roof(name, { 1, 2, 3 }) do
		local bottom, upper = piece.at[2] - piece.size[2] / 2, piece.at[2] + piece.size[2] / 2
		local front, back = piece.at[3] - piece.size[3] / 2, piece.at[3] + piece.size[3] / 2
		local side = math.abs(piece.at[1]) + piece.size[1] / 2
		local fits = bottom < top and upper > top and upper - top <= 0.06 and front >= z0 and back <= z1 and front >= -5.0 and back <= 10.75 and side <= 3.0
		if not fits then
			table.insert(bad2, `{name} {piece.name}`)
		end
		onRoof = onRoof and fits
	end
end
check("every roof stripe sits on the flat roof of both looks (a hair proud, never past its front, back or rounded sides)", onRoof and math.abs(top - Config.Sprinter.Height) < 1e-6, table.concat(bad2, ", "))
check("a roof's pieces: no roof id, no pieces", #Rules.roof(nil, { 1, 1, 1 }) == 0 and #Rules.roof("nope", { 1, 1, 1 }) == 0)

-- the labels whose letters take the stripe's colour: the ZDC logo on both sides and the back door, not the name
local inked = Rules.inked()
check("the parts look's stripe-inked labels: the ZDC logos (Logo, LeafLogo), not the company's name or the plates", inked.Logo == true and inked.LeafLogo == true and inked.CompanyName == nil and inked.FrontPlate == nil)

-- ── The window's swatches ───────────────────────────────────────────────────
local mine = Rules.empty()
Rules.buy(mine, "navy")
local rows = Rules.rows(mine, 450, {}, "paint")
check("the paint swatches in Config's order", #rows == #Rules.Paints and rows[1].id == "cream" and rows[#rows].id == "chrome")
local function row(list: { Rules.Row }, id: string): Rules.Row
	for _, r in list do
		if r.id == id then
			return r
		end
	end
	error(id)
end
check("navy: owned and worn; cream: owned, not worn", row(rows, "navy").owned and row(rows, "navy").worn and row(rows, "cream").owned and not row(rows, "cream").worn)
check("white ($300) with $450: can; black ($600): short $150", row(rows, "white").can and not row(rows, "black").can and row(rows, "black").short == 150)
check("Collector gold: locked with its words, never can", row(rows, "gold").locked and row(rows, "gold").lock == "Collection book: A legendary!" and not row(rows, "gold").can)
check("… unlocked once the milestone is paid", not row(Rules.rows(mine, 450, { legendary = true }, "paint"), "gold").locked)
local liveries = Rules.rows(mine, 2000, {}, "livery")
check("the livery swatches: the stripe on the body you wear (navy), the racing contrast light", #liveries == #Rules.Liveries and same(row(liveries, "racing").body, { 30, 50, 92 })
	and same(row(liveries, "racing").color, P.Contrast.Light) and row(liveries, "zdc").worn and row(liveries, "alpine").can)
check("swatches from junk: still every item, nothing owned but the free", #Rules.rows(nil, nil, nil, "paint") == #Rules.Paints and row(Rules.rows("x", "y", 5, "paint"), "cream").owned and not row(Rules.rows(nil, nil, nil, "paint"), "red").owned)
check("money: whole dollars with commas", Rules.money(20000) == "$20,000" and Rules.money(500) == "$500" and Rules.money(-3) == "$0" and Rules.money(0 / 0) == "$0" and Rules.money(1234567) == "$1,234,567")

-- ── The save ────────────────────────────────────────────────────────────────
local all = Rules.all()
local count, expected = 0, 0
for _ in all.owned do
	count += 1
end
for _, items in { Rules.Paints, Rules.Liveries } do
	for _, item in items do
		expected += if Rules.free(item) then 0 else 1
	end
end
check("all (the admin's): every item but the everybody's, the factory's worn", count == expected and all.owned.gold and all.owned.chrome and all.owned.cream == nil and all.worn.paint == "cream")
local cleaned = Rules.clean({ owned = { red = true, cream = true, junk = true, black = "yes", [5] = true }, worn = { paint = "black", livery = "racing" } })
check("clean: known bought ids only (not the everybody's, not junk); worn only what is owned", same(cleaned.owned, { red = true }) and cleaned.worn.paint == "cream" and cleaned.worn.livery == "zdc")
cleaned = Rules.clean({ owned = { red = true, racing = true }, worn = { paint = "red", livery = "racing" } })
check("… a fine one kept", same(cleaned, { owned = { red = true, racing = true }, worn = { paint = "red", livery = "racing" } }))
check("… a paint worn as a livery (or the other way): the factory's", Rules.clean({ owned = { red = true }, worn = { paint = "zdc", livery = "red" } }).worn.paint == "cream"
	and Rules.clean({ owned = { red = true }, worn = { paint = "zdc", livery = "red" } }).worn.livery == "zdc")
check("… junk: the empty one", same(Rules.clean(nil), Rules.empty()) and same(Rules.clean("x"), Rules.empty()) and same(Rules.clean({ owned = 5, worn = "red" }), Rules.empty()))
local real = { money = 100, [Rules.Flag] = true, vanPaint = { owned = { gold = true }, worn = { paint = "gold", livery = "zdc" } } }
check("fromSave: a real save with the flag keeps its paint", same(Rules.fromSave(real), { owned = { gold = true }, worn = { paint = "gold", livery = "zdc" } }))
check("… without the flag (an older save): the empty one", same(Rules.fromSave({ money = 100, vanPaint = real.vanPaint }), Rules.empty()))
check("… a lock-only record (no money) or nothing: the empty one", same(Rules.fromSave({ [Rules.Flag] = true, vanPaint = real.vanPaint }), Rules.empty()) and same(Rules.fromSave(nil), Rules.empty()))
local once = Rules.fromSave(real)
check("… again on what it gave: the same", same(Rules.fromSave({ money = 1, [Rules.Flag] = true, vanPaint = once }), once))
-- 8.4 review: through an older (8.2) server: it drops vanPaint and its flag but keeps the short keys of `rewards`
local longest = 0
for _, items in { Rules.Paints, Rules.Liveries } do
	for _, item in items do
		longest = math.max(longest, #item.id)
	end
end
check("the rewards keys fit an older server's rewards (40 characters at most, the longest id's \"paintOn:\" too)", #Rules.Worn + longest <= 40
	and #Rules.Owned + longest <= 40 and #Rules.Worn + 32 <= 40, longest)
local rewards: { [string]: boolean } = { ["book:found10"] = true, ["paint:white"] = true, ["paintOn:white"] = true, x = true }
local mine2 = { owned = { red = true, racing = true }, worn = { paint = "red", livery = "racing" } }
Rules.mirror(rewards, mine2)
check("mirror: a key for each item bought and each worn (not the factory's), the stale ones cleared, the others kept", same(rewards, {
	["book:found10"] = true, x = true, ["paint:red"] = true, ["paint:racing"] = true, ["paintOn:red"] = true, ["paintOn:racing"] = true }))
local trip = { money = 100, rewards = rewards } -- (an 8.2 server wrote it again: no vanPaint, no flag)
check("fromSave without the flag: rebuilt from the save's rewards (owned and worn)", same(Rules.fromSave(trip), mine2))
check("… the same as mirrored again (stable)", same(Rules.fromSave({ money = 1, rewards = rewards }), Rules.fromSave(trip)))
local factory = { owned = { gold = true }, worn = { paint = "cream", livery = "zdc" } }
Rules.mirror(rewards, factory)
check("mirror: the factory's worn writes no key; red and racing gone", same(rewards, { ["book:found10"] = true, x = true, ["paint:gold"] = true }))
check("… rebuilt: gold owned, the factory's worn", same(Rules.fromSave({ money = 1, rewards = rewards }), factory))
check("fromRewards: junk keys, a worn one not owned, an everybody's, not `true`: the empty one", same(Rules.fromRewards({ ["paint:nope"] = true, ["paintOn:black"] = true,
	["paint:cream"] = true, ["paint:red"] = "yes", ["paint:"] = true, [5] = true }), Rules.empty()) and same(Rules.fromRewards(nil), Rules.empty()))
check("… a lock-only record (no money) with the keys: the empty one", same(Rules.fromSave({ rewards = { ["paint:red"] = true } }), Rules.empty()))
check("… the flag there: the field wins (never the keys)", same(Rules.fromSave({ money = 1, [Rules.Flag] = true, vanPaint = Rules.empty(), rewards = { ["paint:red"] = true } }), Rules.empty()))
local cleared = { ["paint:red"] = true, ["paintOn:red"] = true }
Rules.mirror(cleared, Rules.empty())
check("mirror of nothing bought: every paint key cleared", next(cleared) == nil)
check("the flag is Config's", Rules.Flag == "vanPaintKept" and P.Flag == Rules.Flag)
check("the remote's rate limit (a few a second)", (Config.Robust.Limits :: any).VanPaint ~= nil and (Config.Robust.Limits :: any).VanPaint >= 1 and (Config.Robust.Limits :: any).VanPaint <= 10)

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
