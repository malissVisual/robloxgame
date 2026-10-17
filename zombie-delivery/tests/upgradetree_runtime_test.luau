-- 10.4 THE UPGRADE TREE AND THE WAREHOUSE IN TWO on the server: the real server/Upgrades.luau, server/Collection.luau,
-- server/PlayerData.luau, server/SandboxTasks.luau and server/VisitorOffers.luau (UpgradesServer.luau and the others
-- through tests/run_tests.py) on tests/runtime/CollectionRuntime.luau's players, DataStore, clock and Net. Checked:
--   1. buying the tree's nodes through the server: a node before its parent refused with the window's reason ("Needs
--      Hall spotlights"), one past the warehouse's tier too ("Needs the Workshop"), a node that comes later and the
--      auction's while the Auction House is shut refused, nothing taken; the parent, the trunk's tier, then the child
--      bought; the window's BUY through the remote (the "bought" message, the showroom a stand bigger, its attribute;
--      a second BUY of the same rank nothing);
--   2. a piece put in the hall and shown for sale (Collection.place, the remote's "place"): the first free stand of each
--      area, the hall's piece earning, the showroom's not; its sale × the showroom's factor (Sales pitch on it); a full
--      showroom and junk refused with words;
--   3. the visitors' offers only for a showroom piece (a hall piece: none, with words), priced from the showroom's price;
--      a VIP buyer's Vip.Pay more for a Rare piece;
--   4. the save: the tree's nodes with their flag and the mirror, the showroom's flag, the pieces where they were; an
--      older save (pieces on hall stands, a FOR SALE sign, no showroomKept) keeps its stands, the sign comes down.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local E = require("./CollectionRuntime")
local Config = require("./Config")
local Rules = require("./UpgradeRules")
local CollectionRules = require("./CollectionRules")
local Visitors = require("./Visitors")
local Market = require("./Market")
local PlayerData = require("./PlayerDataServer")
local Collection = require("./CollectionServer")
local Upgrades = require("./UpgradesServer")
local Tasks = require("./SandboxTasksServer")
local Offers = require("./VisitorOffersServer")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local function kinds(messages: { any }, kind: string): { any }
	local out = {}
	for _, m in messages do
		if type(m) == "table" and m.kind == kind then
			table.insert(out, m)
		end
	end
	return out
end
local function entryOf(player: any, uid: string): any
	for _, entry in Collection.stock(player) do
		if entry.uid == uid then
			return entry
		end
	end
	return nil
end

PlayerData.start()
Collection.start()
Upgrades.start()
Tasks.start()
Offers.start()

local U = Config.SandboxUpgrades
local L = U.List
local SHOW = Config.Showroom.Base
local A = E.join(401, "Ann")
E.plotOf[A] = 1
E.flush()
local profile = PlayerData.get(A) :: any
profile.money = 1000000

-- ── 1. The tree's requirements through the server ─────────────────────────
do
	local cash = profile.money
	local ok, why = Upgrades.buy(A, "idle")
	check("1. a node before its parent: refused with the window's reason, nothing taken", ok == false and why == "Needs Hall spotlights" and profile.money == cash, why)
	ok = Upgrades.buy(A, "lights")
	check("… its parent (Hall spotlights) bought: rank 1 for its price", ok and Rules.level(profile.sandboxUpgrades, "lights") == 1 and profile.money == cash - L.lights.prices[1])
	cash = profile.money
	ok, why = Upgrades.buy(A, "idle")
	check("… the child past the warehouse's tier (the Garage): refused, \"Needs the Workshop\"", ok == false and why == "Needs the Workshop" and profile.money == cash, why)
	ok = Upgrades.buy(A, "warehouse")
	local child = Upgrades.buy(A, "idle")
	check("… the trunk's next tier (the Workshop) bought, then the child", ok and child and Rules.warehouseLevel(profile.sandboxUpgrades) == 2
		and Rules.level(profile.sandboxUpgrades, "idle") == 1 and profile.money == cash - L.warehouse.prices[1] - L.idle.prices[1])
	cash = profile.money
	ok, why = Upgrades.buy(A, "truck")
	check("a node that comes later (the bigger truck): refused with its words", ok == false and why == L.truck.soon and profile.money == cash, why)
	ok, why = Upgrades.buy(A, "auction")
	check("the auction's node while the Auction House is shut: refused", (Config :: any).Auction.On == true or (ok == false and why == "The Auction House opens later"), why)
	-- the window's BUY (the remote)
	E.advance(1)
	local mark = #E.sent
	E.fire(A, "Upgrades", { kind = "buy", id = "showstands", level = 1 })
	E.flush()
	local bought = kinds(E.received(A, "Upgrades", mark), "bought")
	check("the window's BUY: Showroom stands rank 1, the \"bought\" message", #bought == 1 and bought[1].id == "showstands" and bought[1].level == 1)
	check("… the Workshop's showroom one stand bigger (1 + 1), the attribute too", Collection.showStands(A) == 2 and A:GetAttribute(U.Attributes.Show) == 2
		and A:GetAttribute(U.Attributes.Hall) == Collection.stands(A), Collection.showStands(A))
	E.advance(1)
	cash = profile.money
	E.fire(A, "Upgrades", { kind = "buy", id = "showstands", level = 1 })
	E.flush()
	check("… a second BUY of the same rank (a double click): nothing more", Rules.level(profile.sandboxUpgrades, "showstands") == 1 and profile.money == cash)
end

-- ── 2. The hall and the showroom: Collection.place ─────────────────────────
local piano = Collection.add(A, { item = "piano", condition = 1 }) :: string
local gram = Collection.add(A, { item = "gramophone", condition = 1 }) :: string
local sofa = Collection.add(A, { item = "sofa", condition = 1 }) :: string
E.flush()
do
	local ok, _, stand = Collection.place(A, piano, "hall")
	local earns = Collection.incomePerMinute(A)
	check("2. PUT IN THE HALL: the piano on the hall's first free stand, earning", ok and stand ~= nil and not CollectionRules.isShow(stand) and earns > 0, stand)
	ok, _, stand = Collection.place(A, piano, "show")
	check("… SHOW FOR SALE: on the showroom's first plinth (S1); the showroom earns nothing", ok and stand == SHOW + 1 and Collection.incomePerMinute(A) == 0, stand)
	E.advance(1)
	local mark = #E.sent
	E.fire(A, "Collection", { kind = "place", uid = gram, area = "show" })
	E.flush()
	local placed = kinds(E.received(A, "Collection", mark), "placed")
	check("… the remote's place: the gramophone on S2, the client told (area, stand)", #placed == 1 and placed[1].uid == gram and placed[1].area == "show"
		and placed[1].stand == SHOW + 2 and entryOf(A, gram).stand == SHOW + 2)
	local full, fullWhy = Collection.place(A, sofa, "show")
	check("… the showroom full: refused with words, the sofa still in the stock", full == false and fullWhy == "Every showroom stand already shows a piece: take one down or sell it first."
		and entryOf(A, sofa).stand == nil, fullWhy)
	local junk, junkWhy = Collection.place(A, sofa, "attic")
	check("… an area that is neither: refused", junk == false and junkWhy == "Put it in the hall or show it for sale.", junkWhy)
	local state = kinds(E.received(A, "Collection", mark), "state")
	local last = state[#state]
	local view = nil
	for _, v in (last and last.stock) or {} do
		if v.uid == gram then
			view = v
		end
	end
	check("… the state: the showroom's stands and base, the piece's view in the showroom (its price × the factor)", last ~= nil and last.showStands == 2 and last.showBase == SHOW
		and view ~= nil and view.area == "show" and view.price == CollectionRules.sell(entryOf(A, gram), Collection.market(A), Collection.showFactor(A)))
end

-- ── 3. The visitors' offers: only for a showroom piece ─────────────────────
do
	Collection.place(A, piano, "hall")
	E.flush()
	local none, why = Offers.make(A, piano, "tourist", 0.5)
	check("3. no offer for a piece in the hall (it earns there): its words", none == nil and why == "That piece is in the collection hall: not for sale.", why)
	local entry = entryOf(A, gram)
	local market = Collection.market(A)
	local base = CollectionRules.sell(entry, market, Collection.showFactor(A))
	local offer = Offers.make(A, gram, "collector", 0.5)
	check("… one for the showroom's gramophone, from its showroom price", offer ~= nil and offer.base == base and offer.stand == SHOW + 2
		and base == math.floor(CollectionRules.sell(entry, market) * Config.Showroom.SellBonus + 0.5), offer and offer.base)
	Offers.close(A, "left")
	E.advance(Config.Visitors.Offer.Every + 1)
	local rank = CollectionRules.tier(CollectionRules.pieceRarity(entry)).rank
	local plain = Visitors.offerPrice(base, rank, Market.tag(market, entry.item) == "hot", (Visitors.kind(Config.Showroom.Vip.Kind) :: any).pay, 0.5)
	local vip = Offers.make(A, gram, Config.Showroom.Vip.Kind, 0.5)
	check(`… a VIP buyer's for a Rare piece: Vip.Pay ({Config.Showroom.Vip.Pay * 100}%) more`, vip ~= nil and rank >= 3 and vip.price >= plain * (1 + Config.Showroom.Vip.Pay) - 1e-6
		and vip.price <= plain * (1 + Config.Showroom.Vip.Pay) + 10, vip and `{vip.price} vs {plain}`)
	Offers.close(A, "left")
end

-- ── 2b. A showroom sale × the factor, Sales pitch on it ────────────────────
do
	local before = Collection.showFactor(A)
	Upgrades.buy(A, "warehouse") -- (the Storehouse: Sales pitch's tier)
	Upgrades.buy(A, "traffic")
	local pitched = Upgrades.buy(A, "haggle")
	check("2b. Sales pitch bought (Shop window first, the Storehouse): the showroom's factor × 1.06", pitched and math.abs(Collection.showFactor(A) - before * (1 + L.haggle.step)) < 1e-9
		and math.abs(before - Config.Showroom.SellBonus) < 1e-9, Collection.showFactor(A))
	local entry = entryOf(A, gram)
	local want = CollectionRules.sell(entry, Collection.market(A), Collection.showFactor(A))
	local cash = profile.money
	local got = Collection.sell(A, gram)
	check("… the gramophone sold from the showroom: its price × the factor", got == want and profile.money == cash + want and want > CollectionRules.sell(entry, Collection.market(A)), got)
end

-- ── 4. The save ────────────────────────────────────────────────────────────
do
	local levels = Upgrades.levels(A)
	local stands = {}
	for _, entry in Collection.stock(A) do
		stands[entry.uid] = entry.stand or false
	end
	E.leave(A)
	local save = E.saves.Player_401
	check("4. the save: the tree's nodes with their flag, the new ones mirrored in its rewards (an older server keeps the 8.x tracks itself), the showroom's flag",
		save ~= nil and save.upgradeTreeKept == true and save.showroomKept == true and save.sandboxUpgrades.lights == 1 and save.sandboxUpgrades.haggle == 1
		and save.rewards ~= nil and save.rewards["up:haggle:1"] == true and save.rewards["up:idle:1"] == true and save.rewards["up:lights:1"] == nil)
	local back = E.join(401, "Ann")
	E.plotOf[back] = 1
	E.flush()
	local same = true
	for id, level in levels do
		same = same and Rules.level(Upgrades.levels(back), id) == level
	end
	for _, entry in Collection.stock(back) do
		same = same and stands[entry.uid] == (entry.stand or false)
	end
	check("… back: every node, every piece where it was (the piano in the hall)", same and CollectionRules.isShow(entryOf(back, piano).stand) == false)
	E.leave(back)
	-- an older save: pieces on hall stands, a FOR SALE sign, no showroomKept
	E.saves.Player_402 = {
		money = 10, collectionKept = true, warehouseLevelKept = true, sandboxUpgradesKept = true, sandboxUpgrades = { warehouse = 1 },
		collection = { entries = {
			{ uid = "402-1", item = "piano", variant = 1, condition = 1, name = "Upright Piano", stand = 1, got = 1, sale = 2000 },
			{ uid = "402-2", item = "radio", variant = 1, condition = 1, name = "Radio", stand = 2, got = 2 },
		}, nextUid = 3 },
	}
	local old = E.join(402, "Bob")
	E.plotOf[old] = 2
	E.flush()
	local p1, p2 = entryOf(old, "402-1"), entryOf(old, "402-2")
	check("an older save (no showroomKept): its pieces stay on their hall stands (their income as before), the sign down", p1 ~= nil and p1.stand == 1 and p1.sale == nil
		and p2 ~= nil and p2.stand == 2 and Collection.incomePerMinute(old) > 0)
	E.leave(old)
	local resaved = E.saves.Player_402
	check("… saved again with the flags (the migration once)", resaved ~= nil and resaved.showroomKept == true and resaved.upgradeTreeKept == true)
end

if failures > 0 then
	error(`{failures} check(s) failed`)
end
print("ALL CHECKS PASSED")
