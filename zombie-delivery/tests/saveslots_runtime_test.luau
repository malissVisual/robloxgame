-- 10.1, the save slots on the server: the real server/SaveSlots.luau and server/PlayerData.luau (SaveSlotsServer.luau,
-- PlayerDataServer.luau through tests/run_tests.py) on tests/runtime/CollectionRuntime.luau's players, clock, DataStore
-- and Net; CourierAvatar (the looks put on) and TextService (Roblox's filter) the test's stand-ins.
--   * A join reads and locks nothing until the start screen picks: no profile, no DataStore call; the list reads each
--     slot (slot 1 the save of before 10.1: its summary), at most every Config.SaveSlots.Read s (sooner: the same).
--   * A bad slot and a second pick are refused; NEW GAME in slot 2: a fresh game there (written at once, with its
--     courier, its name filtered), slot 1 untouched; READY once it is in, and the courier goes on the body.
--   * Leaving writes the slot played: its time played and when; a rejoin lists slot 2 as the one played last.
--   * CONTINUE slot 1 with a changed courier: its own game, the courier written; START OVER slot 1: a fresh game over it.
--   * A name Roblox cannot filter: none (the game still starts); a PLAY with no pick (SaveSlots.fallback): the slot
--     saved last; leaving on the start screen: nothing read, nothing written.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local E = require("./CollectionRuntime")
local Config = require("./Config")
local task = E.task

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

-- the stand-ins SaveSlots requires (before it is required)
local looks: { { player: any, look: any } } = {}
E.CourierAvatar = {
	setLook = function(player: any, look: any)
		table.insert(looks, { player = player, look = look })
	end,
}
local filterFails = false
E.TextService = {
	FilterStringAsync = function(_self: any, text: string, _userId: number): any
		if filterFails then
			error("TextService: the filter is down (test)")
		end
		return {
			GetNonChatStringForBroadcastAsync = function(): string
				return (string.gsub(text, "badword", "#######"))
			end,
		}
	end,
}

local PlayerData = require("./PlayerDataServer")
local SaveSlots = require("./SaveSlotsServer")

-- An 8.3 save in slot 1 (the save of before 10.1): $2,000, the Workshop, a sofa.
local function save83(cash: number): any
	return {
		money = cash, xp = 0, deliveries = 3, tutorial = true, phone = true, starterKit = true, vestKit = true,
		noPacks = true, noJacket = true, noShoes = true, perGameBags = true, vanOnly = true, carStages = true,
		vanStages = true, xpCurve = 2, cars = { zdcvan = true }, car = "zdcvan",
		collectionKept = true, collection = { entries = { { uid = "1-1", item = "sofa", variant = 1, condition = 0.9, name = "Sofa", stand = 1, got = 1 } }, nextUid = 2 },
		sandboxUpgradesKept = true, warehouseLevelKept = true, sandboxUpgrades = { warehouse = 1 },
	}
end
E.saves.Player_7 = save83(2000)

PlayerData.onMoney = function() end
SaveSlots.start()
PlayerData.start()
check("Config.SaveSlots.On: PlayerData waits for the pick", PlayerData.chooseSlot ~= nil)

-- A join, its PlayerAdded in a thread (its load waits for the pick: task.wait yields only there).
local function join(userId: number): any
	local player = E.player(userId)
	player.Parent = E.Players
	task.spawn(function()
		E.Players.PlayerAdded:Fire(player)
	end)
	E.advance(0.2)
	return player
end
local function last(player: any, from: number?): any
	local list = E.received(player, "Slots", from)
	return list[#list]
end
local function kinds(player: any, from: number): string
	local out = {}
	for _, message in E.received(player, "Slots", from) do
		table.insert(out, message.kind)
	end
	return table.concat(out, ",")
end

-- ── The start screen: nothing read until the pick ─────────────────────────
local p = join(7)
E.advance(5)
check("a join: no profile on the start screen", p ~= nil and PlayerData.get(p) == nil)
check("…and no DataStore call (nothing read, nothing locked)", #E.storeCalls == 0, #E.storeCalls)
local mark = #E.sent
E.fire(p, "Slots", { kind = "list" })
E.advance(0.5)
local list = last(p, mark)
check("the list: every slot", list ~= nil and list.kind == "list" and #list.slots == Config.SaveSlots.Count, list and list.kind)
local one = list and list.slots[1]
check("…slot 1 is the save of before: $2,000, the Workshop (level 2), a piece", one and not one.empty and one.money == 2000 and one.level == 2 and one.pieces == 1,
	one and `{one.money} {one.level} {one.pieces}`)
check("…slots 2 and 3 empty; the one played last: 1; none picked; online", list and list.slots[2].empty and list.slots[3].empty and list.latest == 1
	and list.picked == nil and list.offline == false)
local stored = E.saves.Player_7
check("…read only (the stored save has no lock)", stored.lock == nil)
mark = #E.sent
E.fire(p, "Slots", { kind = "list" })
E.advance(0.2)
check("a list again within Read s: answered from the last read", last(p, mark) ~= nil and last(p, mark).latest == 1)

-- ── NEW GAME in slot 2 ─────────────────────────────────────────────────────
E.advance(1) -- (the remote's rate limit: Config.Robust.Limits.Slots a second)
mark = #E.sent
E.fire(p, "Slots", { kind = "new", slot = 9, look = {} })
check("a slot that does not exist: refused", kinds(p, mark) == "refused", kinds(p, mark))
E.advance(0.5)
mark = #E.sent
E.fire(p, "Slots", { kind = "new", slot = 2, look = { hair = "afro", hat = "cap", skin = "deep", name = "  Big   badword ", junk = true } })
check("NEW GAME in slot 2: loading", kinds(p, mark) == "loading" and last(p, mark).slot == 2, kinds(p, mark))
E.advance(1)
local profile = PlayerData.get(p)
check("…a fresh game: the start's money, nothing collected", profile ~= nil and profile.money == Config.Sandbox.StartMoney and #profile.collection.entries == 0,
	profile and profile.money)
check("…its courier: the look picked, checked", profile and profile.character and profile.character.hair == "afro" and profile.character.skin == "deep"
	and (profile.character :: any).junk == nil)
check("…its name filtered by Roblox and trimmed", profile and profile.character and profile.character.name == "Big #######", profile and profile.character and profile.character.name)
check("…READY sent", string.find(kinds(p, mark), "ready", 1, true) ~= nil, kinds(p, mark))
check("…the courier put on the body", #looks == 1 and looks[1].player == p and looks[1].look.hair == "afro")
check("…PlayerData plays slot 2", PlayerData.slot(p) == 2)
E.advance(1)
local two = E.saves.Player_7_slot2
check("…written at once in slot 2's key, with its courier and this server's lock", two ~= nil and two.money == Config.Sandbox.StartMoney
	and two.character and two.character.hair == "afro" and type(two.lock) == "table")
check("…slot 1 untouched ($2,000, its sofa)", E.saves.Player_7.money == 2000 and #E.saves.Player_7.collection.entries == 1)
mark = #E.sent
E.fire(p, "Slots", { kind = "play", slot = 1 })
check("a second pick: refused (the save is in)", kinds(p, mark) == "refused", kinds(p, mark))

-- ── Leaving, rejoining ─────────────────────────────────────────────────────
PlayerData.addMoney(p, 300)
E.advance(120)
local leftAt = E.now
E.leave(p)
E.advance(1)
two = E.saves.Player_7_slot2
check("the leave save: slot 2, the money, released", two.money == Config.Sandbox.StartMoney + 300 and two.lock == nil, two.money)
check("…the time played (about 2 minutes) and when it was saved", type(two.playTime) == "number" and two.playTime >= 120 and two.playTime < 130
	and math.abs(two.savedAt - leftAt) <= 2, `{two.playTime} {two.savedAt} {leftAt}`)
looks = {}
p = join(7)
mark = #E.sent
E.fire(p, "Slots", { kind = "list" })
E.advance(0.5)
list = last(p, mark)
check("a rejoin's list: slot 2 is the courier's (its name), played last", list and not list.slots[2].empty and list.slots[2].name == "Big #######"
	and list.latest == 2 and list.slots[2].played >= 120, list and list.latest)

-- ── CONTINUE slot 1 with a new look ────────────────────────────────────────
mark = #E.sent
E.fire(p, "Slots", { kind = "play", slot = 1, look = { base = "custom", hair = "bun", name = "Anna" } })
E.advance(1)
profile = PlayerData.get(p)
check("CONTINUE slot 1: its own game ($2,000, the sofa)", profile and profile.money == 2000 and #profile.collection.entries == 1, profile and profile.money)
check("…the courier changed and written at once", profile and profile.character and profile.character.hair == "bun" and E.saves.Player_7.character ~= nil
	and E.saves.Player_7.character.name == "Anna")
check("…the look on the body", #looks == 1 and looks[1].look.hair == "bun")
check("…slot 2 untouched", E.saves.Player_7_slot2.money == Config.Sandbox.StartMoney + 300)
E.leave(p)
E.advance(1)

-- ── START OVER slot 1 ──────────────────────────────────────────────────────
p = join(7)
E.fire(p, "Slots", { kind = "new", slot = 1, look = { base = "own" } })
E.advance(2)
profile = PlayerData.get(p)
check("START OVER slot 1: a fresh game over it (the start's money, no sofa)", profile and profile.money == Config.Sandbox.StartMoney and #profile.collection.entries == 0
	and E.saves.Player_7.money == Config.Sandbox.StartMoney and #E.saves.Player_7.collection.entries == 0)
check("…its own avatar (base own), no name", profile and profile.character and profile.character.base == "own" and profile.character.name == nil)
E.leave(p)
E.advance(1)

-- ── The filter down, the fallback, leaving on the start screen ────────────
filterFails = true
local q = join(8)
E.fire(q, "Slots", { kind = "new", slot = 3, look = { name = "Kate" } })
E.advance(1)
check("a name the filter cannot check: none, the game still starts", PlayerData.get(q) ~= nil and PlayerData.get(q).character.name == nil
	and PlayerData.slot(q) == 3)
filterFails = false
local r = join(9)
SaveSlots.fallback(r)
E.advance(1)
check("PLAY with no pick (the fallback): slot 1, CONTINUE", PlayerData.get(r) ~= nil and PlayerData.slot(r) == 1)
local calls = #E.storeCalls
local s = join(10)
E.advance(3)
E.leave(s)
E.advance(2)
check("leaving on the start screen: nothing read or written", #E.storeCalls == calls and E.saves.Player_10 == nil, #E.storeCalls - calls)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
