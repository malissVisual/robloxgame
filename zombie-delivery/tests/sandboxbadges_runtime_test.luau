-- 8.3 SANDBOX, the Roblox badges on the server: the real server/SandboxBadges.luau with the real server/PlayerData.luau,
-- server/Collection.luau and server/Upgrades.luau (SandboxBadgesServer.luau, PlayerDataServer.luau, CollectionServer.luau,
-- UpgradesServer.luau through tests/run_tests.py) on tests/runtime/CollectionRuntime.luau's players, DataStore, clock
-- and Net; Roblox's BadgeService a fake (it records every call, owns what it awarded, errors or says no on cue),
-- server/Moving.luau's onResult and server/SandboxLeaders.luau's rows the test's stand-ins. Checked:
--   * every id 0 (as shipped): BadgeService is never called, whatever happens; the moves are still counted; the admins'
--     line says nothing is set up;
--   * each badge from its moment (a move finished, clean, the tenth, the crew's; a sale, a hot one; a legendary home; a
--     piece on show; an upgrade, the warehouse at level 5; the PAINT shop; the book full; the TOP MOVERS board on a full
--     server) awarded once (8.3: a veteran's free Big Warehouse is no upgrade; a warehouse level bought is, its moment): UserHasBadgeAsync once, then AwardBadgeAsync once, never again this session; one already
--     owned is never awarded; a badge whose id is 0 among the others is never asked about;
--   * errors swallowed: UserHasBadgeAsync failing (the award tried anyway), AwardBadgeAsync failing (tried again Wait s
--     later, Tries times, then given up for the session), Roblox saying no (never asked again); nothing reaches the
--     game; a player leaving mid-retry: no more calls;
--   * Studio: nothing awarded (no call) unless Config.SandboxBadges.Studio;
--   * the save: the moves' counter written with its flag and read back; a milestone reached earlier is awarded on the
--     next join (a new session asks again, once); a save without the flag counts from 0.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local E = require("./CollectionRuntime")
local Config = require("./Config")
Config.Sandbox.On = true
local B = Config.SandboxBadges
local Rules = require("./SandboxBadgeRules")
local CollectionBookRules = require("./CollectionBookRules")
local VanPaintRules = require("./VanPaintRules")
local Market = require("./Market")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

E.now = 20372 * 86400 + 12 * 3600 -- (a fixed day: the market's hot kinds)

-- ── Roblox's BadgeService: a fake ──────────────────────────────────────────
type Call = { what: string, userId: number, id: number }
local Fake = {
	owned = {} :: { [string]: boolean }, -- "userId:id"
	calls = {} :: { Call },
	hasErrors = 0, -- the next UserHasBadgeAsync calls that error
	awardErrors = 0, -- the next AwardBadgeAsync calls that error
	refuse = {} :: { [number]: boolean }, -- ids AwardBadgeAsync says no to
}
local BadgeService: any = {}
function BadgeService.UserHasBadgeAsync(_self: any, userId: number, id: number): boolean
	table.insert(Fake.calls, { what = "has", userId = userId, id = id })
	if Fake.hasErrors > 0 then
		Fake.hasErrors -= 1
		error("HTTP 500 (Internal Server Error) (fake)")
	end
	return Fake.owned[`{userId}:{id}`] == true
end
function BadgeService.AwardBadgeAsync(_self: any, userId: number, id: number): boolean
	table.insert(Fake.calls, { what = "award", userId = userId, id = id })
	if Fake.awardErrors > 0 then
		Fake.awardErrors -= 1
		error("HTTP 503 (Service Unavailable) (fake)")
	end
	if Fake.refuse[id] then
		return false
	end
	Fake.owned[`{userId}:{id}`] = true
	return true
end
local baseService = E.game.GetService
E.game.GetService = function(self: any, name: string): any
	if name == "BadgeService" then
		return BadgeService
	end
	return baseService(self, name)
end

-- How many calls of `what` ("has" | "award" | nil: both) for this player (and this badge) since `from`.
local function calls(what: string?, player: any?, key: string?, from: number?): number
	local n = 0
	local id = if key then B.Badges[key].id else nil
	for index = (from or 0) + 1, #Fake.calls do
		local c = Fake.calls[index]
		if (what == nil or c.what == what) and (player == nil or c.userId == player.UserId) and (id == nil or c.id == id) then
			n += 1
		end
	end
	return n
end

-- ── server/Moving.luau's onResult and server/SandboxLeaders.luau's rows: the test's ─────
local results: { (any, any, any, any) -> () } = {}
E.Moving = {
	onResult = function(fn: any)
		table.insert(results, fn)
	end,
}
-- A move of `owner`'s ends (done unless `how`): one piece home, `broken` broken; `crew` (default: the owner alone).
local function finish(owner: any, broken: number?, how: string?, crew: { any }?)
	local move = { order = { 1, 2 }, things = { [1] = { state = "delivered" }, [2] = { state = "ground" } } }
	for _, fn in results do
		fn(owner, move, { how = how or "done", broken = broken or 0 }, crew or { owner })
	end
	E.flush()
end
local board: { any } = {}
E.SandboxLeaders = {
	rows = function(): { any }
		return board
	end,
}

local PlayerData = require("./PlayerDataServer")
local Collection = require("./CollectionServer")
local Upgrades = require("./UpgradesServer")
local Badges = require("./SandboxBadgesServer")
PlayerData.start()
Collection.start()
Upgrades.start()
Badges.start()
check("the hook: Moving.onResult registered once", #results == 1)

local function profileOf(player: any): any
	return PlayerData.get(player) :: any
end
local function uidOf(player: any, item: string): string?
	for _, entry in Collection.stock(player) do
		if entry.item == item and entry.stand == nil then
			return entry.uid
		end
	end
	return nil
end
local function joinAdmin(userId: number, name: string): any
	local player = E.player(userId, name)
	player:SetAttribute("Admin", true)
	player.Parent = E.Players
	E.Players.PlayerAdded:Fire(player)
	E.flush()
	return player
end

-- The pieces the test needs: a legendary one, today's hot kind, a plain one that isn't hot (and fits a Garage's stand).
local legendaryItem: string = "oil_painting"
for _, item in CollectionBookRules.Pieces do
	if CollectionBookRules.rarityOf(item) == "legendary" then
		legendaryItem = item
		break
	end
end
local picks = Market.pick(Market.dayOf(E.now))
local hotItem = picks.hot[1]
local plainItem = "box"
for _, item in { "box", "plant", "lamp", "chair", "stool" } do
	if not table.find(picks.hot, item) then
		plainItem = item
		break
	end
end

-- ── Every id 0 (as shipped): nothing is ever asked ─────────────────────────
local admin = joinAdmin(90, "Owner")
check("ids 0: the admins' line says nothing is set up", string.find(tostring(admin:GetAttribute("AdminBadges")), "No badge is set up", 1, true) ~= nil,
	admin:GetAttribute("AdminBadges"))
local A = E.join(101, "Ann")
E.plotOf[A] = 1
PlayerData.addMoney(A, 100000, "Admin")
finish(A, 0)
finish(A, 0, "late", { A, admin })
Collection.add(A, { item = legendaryItem, condition = 1 })
Collection.add(A, { item = hotItem, condition = 1 })
Collection.add(A, { item = plainItem, condition = 1 })
E.flush()
Collection.display(A, uidOf(A, plainItem) :: string, 1)
Collection.sell(A, uidOf(A, hotItem) :: string)
Upgrades.buy(A, "lights")
Upgrades.admin(A, "level5")
VanPaintRules.buy(profileOf(A).vanPaint, "white")
PlayerData.notify(A)
board = { { userId = 101, value = 9000, rank = 1 }, { userId = 90, value = 5, rank = 2 }, { userId = 1, value = 0, rank = 3 }, { userId = 2, value = 0, rank = 4 } }
E.advance(B.TopEvery + 1)
check("ids 0: BadgeService never called (moves, a sale, a legendary, a stand, upgrades, paint, the board)", #Fake.calls == 0, #Fake.calls)
check("ids 0: the moves still counted (the owner's two, the crew's one)", profileOf(A).sandboxMoves == 2 and profileOf(admin).sandboxMoves == 1,
	profileOf(A).sandboxMoves)
check("ids 0: no session entries", next(Badges.session(A)) == nil and Badges.awarded() == 0)

-- ── The badges set up (topMover still 0) ───────────────────────────────────
local ID: { [string]: number } = {}
for index, key in Rules.Order do
	ID[key] = 2_000_000_000 + index
	B.Badges[key].id = ID[key]
end
B.Badges.topMover.id = 0

local Bea = E.join(102, "Bea")
E.plotOf[Bea] = 2
check("set up: a new player joining earns nothing (no call)", calls(nil, Bea) == 0)
finish(Bea, 0)
local session = Badges.session(Bea)
check("a clean move finished: firstMove and cleanMove awarded (the fake owns them)", session.firstMove == "awarded" and session.cleanMove == "awarded"
	and Fake.owned[`102:{ID.firstMove}`] and Fake.owned[`102:{ID.cleanMove}`], session.firstMove)
check("… each asked once (UserHasBadgeAsync), then awarded once (AwardBadgeAsync); tenMoves not yet", calls("has", Bea, "firstMove") == 1
	and calls("award", Bea, "firstMove") == 1 and calls("has", Bea, "cleanMove") == 1 and calls("award", Bea, "cleanMove") == 1 and calls(nil, Bea, "tenMoves") == 0)
local mark = #Fake.calls
finish(Bea, 1)
finish(Bea, 0, "late")
check("two more moves: no call again (once a session)", calls(nil, Bea, nil, mark) == 0 and profileOf(Bea).sandboxMoves == 3, profileOf(Bea).sandboxMoves)
finish(Bea, 0, "cancelled")
finish(Bea, 0, "failed")
check("a move called off or lost is no finished move (not counted)", profileOf(Bea).sandboxMoves == 3)
for _ = 4, 9 do
	finish(Bea, 2)
end
check("nine moves: no tenMoves yet", calls(nil, Bea, "tenMoves") == 0 and profileOf(Bea).sandboxMoves == 9)
finish(Bea, 2)
check("the tenth: tenMoves awarded once", Badges.session(Bea).tenMoves == "awarded" and calls("award", Bea, "tenMoves") == 1 and profileOf(Bea).sandboxMoves == 10)
finish(Bea, 2)
check("… the eleventh: no call", calls("award", Bea, "tenMoves") == 1 and calls("has", Bea, "tenMoves") == 1)

-- The crew: everybody in it finished the move.
local Cid = E.join(103, "Cid")
mark = #Fake.calls
finish(Bea, 0, "done", { Bea, Cid })
check("a crew mate: firstMove and cleanMove for them too (their own counter)", Badges.session(Cid).firstMove == "awarded" and Badges.session(Cid).cleanMove == "awarded"
	and profileOf(Cid).sandboxMoves == 1 and calls(nil, Bea, nil, mark) == 0)

-- Sales: the first, then a hot one.
Collection.add(Bea, { item = plainItem, condition = 1 })
Collection.add(Bea, { item = plainItem, condition = 1 })
Collection.add(Bea, { item = hotItem, condition = 1 })
Collection.add(Bea, { item = hotItem, condition = 1 })
E.flush()
mark = #Fake.calls
Collection.sell(Bea, uidOf(Bea, plainItem) :: string)
E.flush()
check(`a sale ({plainItem}, not hot): firstSale only`, Badges.session(Bea).firstSale == "awarded" and calls("award", Bea, "firstSale") == 1 and calls(nil, Bea, "hotSale") == 0)
Collection.sell(Bea, uidOf(Bea, hotItem) :: string)
E.flush()
check(`a hot piece sold ({hotItem}): hotSale; firstSale not again`, Badges.session(Bea).hotSale == "awarded" and calls("award", Bea, "hotSale") == 1
	and calls(nil, Bea, "firstSale") == 2)
Collection.sell(Bea, uidOf(Bea, hotItem) :: string)
E.flush()
check("… another hot sale: no call", calls(nil, Bea, "hotSale") == 2 and calls(nil, Bea, "firstSale") == 2)

-- A legendary home, a piece on show.
Collection.add(Bea, { item = legendaryItem, condition = 0.7 })
E.flush()
check(`a legendary home ({legendaryItem}): legendary awarded once`, Badges.session(Bea).legendary == "awarded" and calls("award", Bea, "legendary") == 1)
Collection.add(Bea, { item = legendaryItem, condition = 1 })
E.flush()
check("… a second one: no call", calls(nil, Bea, "legendary") == 2)
check("nothing on show yet: no firstShow", calls(nil, Bea, "firstShow") == 0)
Collection.display(Bea, uidOf(Bea, plainItem) :: string, 1)
E.flush()
check("a piece on a stand: firstShow (at the frame's end)", Badges.session(Bea).firstShow == "awarded" and calls("award", Bea, "firstShow") == 1)

-- The upgrades, the warehouse at level 5.
PlayerData.addMoney(Bea, 200000, "Admin")
local bought = Upgrades.buy(Bea, "engine")
E.flush()
check("an upgrade bought (Van engine): firstUpgrade", bought and Badges.session(Bea).firstUpgrade == "awarded" and calls("award", Bea, "firstUpgrade") == 1
	and calls(nil, Bea, "warehouse5") == 0)
for _ = 1, 3 do
	Upgrades.buy(Bea, "warehouse")
	E.flush()
end
check("the warehouse at level 4: no warehouse5 yet", Upgrades.warehouseLevel(Bea) == 4 and calls(nil, Bea, "warehouse5") == 0, Upgrades.warehouseLevel(Bea))
Upgrades.buy(Bea, "warehouse")
E.flush()
check("… at level 5: warehouse5; firstUpgrade not again", Upgrades.warehouseLevel(Bea) == 5 and Badges.session(Bea).warehouse5 == "awarded"
	and calls("award", Bea, "warehouse5") == 1 and calls("award", Bea, "firstUpgrade") == 1)

-- The PAINT shop (server/VanPaint.luau's order: the money first, then the item owned and worn).
PlayerData.spend(Bea, 300, "VanPaint", "white")
VanPaintRules.buy(profileOf(Bea).vanPaint, "white")
E.flush()
check("a paint bought: painted (looked at after the purchase, at the frame's end)", Badges.session(Bea).painted == "awarded" and calls("award", Bea, "painted") == 1)

-- The book full (the admin's FILL BOOK, a player's long game).
check("the book not full: no fullBook", calls(nil, Bea, "fullBook") == 0)
CollectionBookRules.fill(profileOf(Bea).collectionBook)
PlayerData.notify(Bea)
E.flush()
check("the book full: fullBook", Badges.session(Bea).fullBook == "awarded" and calls("award", Bea, "fullBook") == 1)

-- Once a session, all of it.
local once = true
for _, key in Rules.Order do
	once = once and calls("has", Bea, key) <= 1 and calls("award", Bea, key) <= 1
end
check("once a session: never two checks or two awards of one badge", once)

-- ── 8.3: a save from before 8.3 (the Big Warehouse for free); a warehouse level bought ─────────────────
E.saves.Player_120 = {
	money = 50000, xp = 0, deliveries = 3, tutorial = true, phone = true, starterKit = true, vestKit = true,
	noPacks = true, noJacket = true, noShoes = true, perGameBags = true, vanOnly = true, carStages = true,
	vanStages = true, xpCurve = 2, cars = { zdcvan = true }, car = "zdcvan",
}
local Vet = E.join(120, "Vet")
E.plotOf[Vet] = 3
E.flush()
check("8.3: a veteran's save (from before 8.3: the warehouse at level 4 for free), nothing bought: no firstUpgrade", Upgrades.warehouseLevel(Vet) == 4
	and calls(nil, Vet, "firstUpgrade") == 0 and Badges.session(Vet).firstUpgrade == nil)
local Neo = E.join(121, "Neo")
E.plotOf[Neo] = 4
PlayerData.addMoney(Neo, 5000, "Admin")
E.flush()
local grew = Upgrades.buy(Neo, "warehouse")
E.flush()
check("8.3: a new player buys the Workshop (the Deliveros Warehouse's first level): firstUpgrade, from the purchase's moment (Upgrades.onBought)", grew
	and Upgrades.warehouseLevel(Neo) == 2 and Badges.session(Neo).firstUpgrade == "awarded" and calls("award", Neo, "firstUpgrade") == 1)

-- ── A badge already owned ──────────────────────────────────────────────────
local Dot = E.join(104, "Dot")
Fake.owned[`104:{ID.firstMove}`] = true
finish(Dot, 1)
finish(Dot, 1)
check("owned already: asked once, never awarded (owned), not asked again", Badges.session(Dot).firstMove == "owned" and calls("has", Dot, "firstMove") == 1
	and calls("award", Dot, "firstMove") == 0)

-- ── id 0 among the others; the TOP MOVERS board ─────────────────────────────
board = { { userId = 103, value = 9000, rank = 1 }, { userId = 102, value = 400, rank = 2 }, { userId = 104, value = 0, rank = 3 }, { userId = 101, value = 0, rank = 4 } }
Collection.add(Cid, { item = plainItem, condition = 1 })
E.advance(B.TopEvery + 1)
check("topMover at id 0: the board's leader is never asked about", calls(nil, nil, nil) > 0 and Badges.session(Cid).topMover == nil
	and #(function(): { any }
		local out = {}
		for _, c in Fake.calls do
			if c.id == 0 then
				table.insert(out, c)
			end
		end
		return out
	end)() == 0)
B.Badges.topMover.id = 2_000_000_099
ID.topMover = 2_000_000_099
board = { board[1], board[2], board[3] }
Collection.add(Cid, { item = plainItem, condition = 1 })
E.advance(B.TopEvery + 1)
check("the board with 3 players (not full): nobody", calls(nil, nil, "topMover") == 0)
board = { { userId = 103, value = 500, rank = 1 }, { userId = 102, value = 500, rank = 1 }, { userId = 104, value = 10, rank = 3 }, { userId = 101, value = 0, rank = 4 } }
Collection.add(Cid, { item = plainItem, condition = 1 })
E.advance(B.TopEvery + 1)
check("a tie at the top of a full board: nobody", calls(nil, nil, "topMover") == 0)
board = { { userId = 103, value = 9000, rank = 1 }, { userId = 102, value = 400, rank = 2 }, { userId = 104, value = 0, rank = 3 }, { userId = 101, value = 0, rank = 4 } }
Collection.add(Cid, { item = plainItem, condition = 1 })
E.advance(B.TopEvery + 1)
check("alone at the top of a full board (4 players): topMover for them", Badges.session(Cid).topMover == "awarded" and calls("award", Cid, "topMover") == 1
	and calls(nil, Bea, "topMover") == 0)
Collection.add(Bea, { item = plainItem, condition = 1 })
E.advance(B.TopEvery + 1)
check("… still on top: no call again", calls(nil, Cid, "topMover") == 2)

-- ── Errors swallowed ───────────────────────────────────────────────────────
local Eve = E.join(105, "Eve")
Collection.add(Eve, { item = plainItem, condition = 1 })
Collection.add(Eve, { item = hotItem, condition = 1 })
Collection.add(Eve, { item = hotItem, condition = 1 })
E.flush()
local warnings = #E.warnings
Fake.hasErrors, Fake.awardErrors = 1, 2
local ok, err = pcall(function()
	Collection.sell(Eve, uidOf(Eve, plainItem) :: string)
	E.flush()
end)
check("UserHasBadgeAsync and AwardBadgeAsync erroring: nothing reaches the game (the sale went through)", ok and Collection.stock(Eve)[1] ~= nil
	and profileOf(Eve).money > Config.Sandbox.StartMoney, err)
check("… the check failed, the award failed once: waiting to try again", Badges.session(Eve).firstSale == "busy" and calls("award", Eve, "firstSale") == 1)
E.advance(B.Wait + 0.1)
check("… Wait s later: failed again", Badges.session(Eve).firstSale == "busy" and calls("award", Eve, "firstSale") == 2)
E.advance(B.Wait + 0.1)
check("… the third try: awarded (Tries 3); the checks once", Badges.session(Eve).firstSale == "awarded" and calls("award", Eve, "firstSale") == 3
	and calls("has", Eve, "firstSale") == 1 and Fake.owned[`105:{ID.firstSale}`] == true)
check("… warned (once each), never thrown", #E.warnings > warnings and #E.warnings <= warnings + 2, #E.warnings - warnings)
Fake.awardErrors = 99
Collection.sell(Eve, uidOf(Eve, hotItem) :: string)
E.flush()
E.advance(B.Wait * B.Tries + 1)
check("AwardBadgeAsync failing every time: given up after Tries (3 calls), \"failed\"", Badges.session(Eve).hotSale == "failed" and calls("award", Eve, "hotSale") == B.Tries)
Collection.sell(Eve, uidOf(Eve, hotItem) :: string)
E.flush()
E.advance(B.Wait * B.Tries + 1)
check("… another hot sale: not asked again this session", calls(nil, Eve, "hotSale") == B.Tries + 1)
Fake.awardErrors = 0
Fake.refuse[ID.firstMove] = true
finish(Eve, 1)
finish(Eve, 1)
check("Roblox saying no (false): \"refused\", never asked again this session", Badges.session(Eve).firstMove == "refused" and calls("award", Eve, "firstMove") == 1
	and calls("has", Eve, "firstMove") == 1)
Fake.refuse[ID.firstMove] = nil

-- A player leaving mid-retry: no more calls.
local Fay = E.join(106, "Fay")
Fake.awardErrors = 1
finish(Fay, 1)
check("an award failed once for Fay", calls("award", Fay, "firstMove") == 1)
E.leave(Fay)
E.advance(B.Wait * B.Tries + 1)
check("… she left before the retry: no more calls, her session gone", calls("award", Fay, "firstMove") == 1 and next(Badges.session(Fay)) == nil)
Fake.awardErrors = 0

-- ── Studio ─────────────────────────────────────────────────────────────────
E.studio = true
local Gus = E.join(107, "Gus")
finish(Gus, 0)
Collection.add(Gus, { item = legendaryItem, condition = 1 })
E.flush()
check("Studio (Config.SandboxBadges.Studio off): no call at all, the moves still counted", calls(nil, Gus) == 0 and profileOf(Gus).sandboxMoves == 1)
admin:SetAttribute("AdminBadges", nil)
B.Studio = true
finish(Gus, 1)
check("Studio with the flag on: awarded", Badges.session(Gus).firstMove == "awarded" and calls("award", Gus, "firstMove") == 1)
check("… the admins' line: every badge set up, awarded here, the count", string.find(tostring(admin:GetAttribute("AdminBadges")), `{#Rules.Order} of {#Rules.Order} set up`, 1, true) ~= nil
	and string.find(tostring(admin:GetAttribute("AdminBadges")), `{Badges.awarded()} awarded`, 1, true) ~= nil, admin:GetAttribute("AdminBadges"))
B.Studio = false
E.studio = false

-- ── The save; the next session ─────────────────────────────────────────────
local beaMoves = profileOf(Bea).sandboxMoves
E.leave(Bea)
local stored = E.saves.Player_102
check("the save: the moves' counter with its flag", stored ~= nil and stored.sandboxMoves == beaMoves and stored.sandboxMovesKept == true, stored and stored.sandboxMoves)
mark = #Fake.calls
local awardedBefore = Badges.awarded()
local Bea2 = E.join(102, "Bea")
E.flush()
check("Bea back: the counter read back", profileOf(Bea2).sandboxMoves == beaMoves)
local stateKeys = Rules.fromState(Rules.stateOf(profileOf(Bea2), true))
local askedOnce = true
for _, key in stateKeys do
	askedOnce = askedOnce and calls("has", Bea2, key, mark) == 1 and Badges.session(Bea2)[key] == "owned"
end
check("… a new session: her state's badges asked once each (owned), none awarded again", #stateKeys >= 6 and askedOnce and calls("award", Bea2, nil, mark) == 0
	and Badges.awarded() == awardedBefore, #stateKeys)

-- A save from before the badges were set up, written with the flag: its milestones awarded on joining.
local save = {
	money = 900, xp = 0, tutorial = true, phone = true, starterKit = true, vestKit = true, noPacks = true, noJacket = true, noShoes = true,
	perGameBags = true, vanOnly = true, carStages = true, vanStages = true, xpCurve = 2, cars = { zdcvan = true },
	car = "zdcvan", sandboxMovesKept = true, sandboxMoves = 12, vanPaintKept = true,
	vanPaint = { owned = { racing = true }, worn = { paint = "cream", livery = "racing" } },
}
E.saves.Player_108 = save
local Hal = E.join(108, "Hal")
E.flush()
local hal = Badges.session(Hal)
check("an earlier save (12 moves, a livery bought): firstMove, tenMoves, painted awarded on joining", hal.firstMove == "awarded" and hal.tenMoves == "awarded"
	and hal.painted == "awarded" and hal.cleanMove == nil and hal.firstShow == nil and profileOf(Hal).sandboxMoves == 12)
local old = table.clone(save)
old.sandboxMovesKept = nil
E.saves.Player_109 = old
local Ida = E.join(109, "Ida")
E.flush()
check("a save without the flag: the counter starts at 0 (no firstMove)", profileOf(Ida).sandboxMoves == 0 and Badges.session(Ida).firstMove == nil
	and Badges.session(Ida).painted == "awarded")

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
