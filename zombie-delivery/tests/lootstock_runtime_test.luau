-- 9.x LOOT in the stock: the real server/Collection.luau, server/CollectionBook.luau and server/PlayerData.luau
-- (CollectionServer.luau, CollectionBookServer.luau, PlayerDataServer.luau through tests/run_tests.py) on
-- tests/runtime/CollectionRuntime.luau's players, DataStore, clock and Net. A piece's rarity from its house's roll
-- (Collection.add's `rarity`, server/Loot.luau through the trip home) is the same everywhere after:
--   * the stock keeps it (another tier than its item's own; its own and junk keep none: they read as its own), the
--     state's view shows its rarity, its lifted value, its income and price at its tier; the analytics' rarest is it;
--   * the book's page keeps the rarest found (top);
--   * a deal between players (Collection.transfer) gives the buyer the same rarity and value (the book: bought, at it);
--   * the save round trip keeps it; an older save's piece (none) reads as its own.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local E = require("./CollectionRuntime")
local Config = require("./Config")
local Rules = require("./CollectionRules")
local PlayerData = require("./PlayerDataServer")
local Collection = require("./CollectionServer")
local CollectionBook = require("./CollectionBookServer")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local events: { { name: string, value: any, a: any } } = {}
PlayerData.analytics.event = function(_player: any, name: any, value: any, a: any)
	table.insert(events, { name = name, value = value, a = a })
end
local function stateOf(player: any, from: number?): any
	local found = nil
	for _, m in E.received(player, "Collection", from) do
		if type(m) == "table" and m.kind == "state" then
			found = m
		end
	end
	return found
end
local function viewOf(state: any, uid: string): any
	for _, view in (state and state.stock) or {} do
		if view.uid == uid then
			return view
		end
	end
	return nil
end

PlayerData.start()
Collection.start()
CollectionBook.start()

local LIFT2 = math.floor(350 * Config.Loot.Lift ^ 2 + 0.5) -- (a sofa, Uncommon, rolled two tiers up: Epic)
local ann = E.join(501, "Ann")
local bob = E.join(502, "Bob")
local mark = #E.sent
local u1 = Collection.add(ann, { item = "sofa", condition = 1, rarity = "epic" }) :: string
local u2 = Collection.add(ann, { item = "sofa", condition = 1, rarity = "uncommon" }) :: string
local u3 = Collection.add(ann, { item = "sofa", condition = 1, rarity = "gold" } :: any) :: string
local u4 = Collection.add(ann, { item = "sofa", condition = 1 }) :: string
local stock: { [string]: any } = {}
for _, entry in Collection.stock(ann) do
	stock[entry.uid] = entry
end
check("the stock keeps a roll's rarity (Epic), none for its own (Uncommon), junk or none given", stock[u1].rarity == "epic" and stock[u2].rarity == nil and stock[u3].rarity == nil and stock[u4].rarity == nil)
E.flush()
local state = stateOf(ann, mark)
local v1, v4 = viewOf(state, u1), viewOf(state, u4)
check("the state's view: the Epic sofa Epic and worth the lift, the others Uncommon at $350", v1 and v1.rarity == "epic" and v1.value == LIFT2 and v4 and v4.rarity == "uncommon" and v4.value == 350)
check("… its income and price at the Epic tier (more than its plain twin's)", v1 and v4 and v1.income > v4.income and v1.price > v4.price
	and v1.price == math.max(1, math.floor(LIFT2 * Config.Collection.Tiers.epic.sell + 0.5)), v1 and v1.price)
local added = nil
for _, event in events do
	if event.name == "CollectionAdded" then
		added = event
	end
end
check("analytics: the frame's rarest is the roll's (Epic)", added ~= nil and added.a == "epic" and added.value == 4, added and added.a)
local page = (CollectionBook.book(ann) :: any).sofa
check("the book's page: four sofas, its rarest found Epic", page ~= nil and page.n == 4 and page.top == "epic")

-- a deal between players: the same rarity and value at the buyer's
local showStand = Config.Showroom.Base + 1 -- (10.4: a deal is a showroom piece's; a sofa's plinth from the Workshop on)
local annProfile = PlayerData.get(ann) :: any
annProfile.sandboxUpgrades.warehouse = 1
local shownOk, shownWhy = Collection.display(ann, u1, showStand)
check("the Epic sofa on showroom stand 1", shownOk, shownWhy)
local piece = Collection.transfer(ann, bob, u1, showStand, 200, 16)
check("a deal (Collection.transfer): the buyer's piece Epic too", piece ~= nil and piece.rarity == "epic" and Rules.valueOf(piece) == LIFT2)
E.flush()
local bobView = viewOf(stateOf(bob), (piece :: any).uid)
check("… the buyer's state shows it Epic, worth the same", bobView ~= nil and bobView.rarity == "epic" and bobView.value == LIFT2)
local bobPage = (CollectionBook.book(bob) :: any).sofa
check("… the buyer's book: bought, at Epic", bobPage ~= nil and bobPage.bought == true and bobPage.top == "epic")

-- the save round trip
E.leave(bob)
local saved = E.saves.Player_502
check("the save writes the rarity with the piece", saved ~= nil and saved.collection.entries[1].rarity == "epic" and saved.collectionBook.sofa.top == "epic")
local bob2 = E.join(502, "Bob")
local back = Collection.stock(bob2)[1]
check("rejoining: the same rarity, the same value", back ~= nil and back.rarity == "epic" and Rules.valueOf(back) == LIFT2 and (CollectionBook.book(bob2) :: any).sofa.top == "epic")
-- an older save's piece: no rarity, its own
E.leave(bob2)
E.saves.Player_502.collection.entries[1].rarity = nil
local bob3 = E.join(502, "Bob")
local old = Collection.stock(bob3)[1]
check("a piece saved before 9.x (no rarity): its own rarity and value", old ~= nil and old.rarity == nil and Rules.pieceRarity(old) == "uncommon" and Rules.valueOf(old) == 350)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
