-- 9.6, the save slots' rules (shared/SaveSlotRules.luau, Config.SaveSlots): the keys (slot 1 the save of before 9.6),
-- a slot asked for (only a whole number in range), a real save against a lock-only record, the summary of an empty
-- slot, of a save of today (its courier, the warehouse's level, the money, the pieces, the moves, the time played,
-- when it was saved), of a save from before 8.3 (the Big Warehouse, level 4) and of junk; the slot saved last; the
-- time played, "saved … ago" and the money as the cards write them.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local SaveSlotRules = require("./SaveSlotRules")
local Config = require("./Config")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

check("Config.SaveSlots: 2 … 5 slots, a name 2 … 24 letters, a read pause", Config.SaveSlots.Count >= 2 and Config.SaveSlots.Count <= 5
	and Config.SaveSlots.NameMin >= 1 and Config.SaveSlots.NameMax <= 24 and Config.SaveSlots.Read > 0)

-- ── Keys and slots ─────────────────────────────────────────────────────────
check("key: slot 1 is the save of before (Player_<id>)", SaveSlotRules.key(42, 1) == "Player_42")
check("key: slot 2 and 3 their own", SaveSlotRules.key(42, 2) == "Player_42_slot2" and SaveSlotRules.key(42, 3) == "Player_42_slot3")
check("slot: 1 … Count", SaveSlotRules.slot(1) == 1 and SaveSlotRules.slot(Config.SaveSlots.Count) == Config.SaveSlots.Count)
check("slot: 0, Count + 1, 1.5, NaN, a string, nil: none", SaveSlotRules.slot(0) == nil and SaveSlotRules.slot(Config.SaveSlots.Count + 1) == nil
	and SaveSlotRules.slot(1.5) == nil and SaveSlotRules.slot(0 / 0) == nil and SaveSlotRules.slot("1") == nil and SaveSlotRules.slot(nil) == nil)
check("real: money in it; a lock-only record, nil and junk are not", SaveSlotRules.real({ money = 0 }) and not SaveSlotRules.real({ lock = { job = "x" } })
	and not SaveSlotRules.real(nil) and not SaveSlotRules.real("save") and not SaveSlotRules.real({ money = "5" }))

-- ── Summaries ──────────────────────────────────────────────────────────────
do
	local empty = SaveSlotRules.summary(2, nil)
	check("an empty slot: empty, level 1, nothing in it", empty.slot == 2 and empty.empty and empty.level == 1 and empty.money == 0 and empty.pieces == 0 and empty.name == nil)
	check("a lock-only record: empty", SaveSlotRules.summary(1, { lock = { job = "j", at = 5 } }).empty)
	local now = 1760000000
	local saved = {
		money = 12400.7, collectionKept = true,
		collection = { entries = {
			{ uid = "1-1", item = "sofa", variant = 1, condition = 0.9, name = "Sofa", got = 1 },
			{ uid = "1-2", item = "lamp", variant = 1, condition = 0.5, name = "Lamp", got = 2 },
		}, nextUid = 3 },
		sandboxUpgradesKept = true, warehouseLevelKept = true, sandboxUpgrades = { warehouse = 2 },
		sandboxMovesKept = true, sandboxMoves = 7,
		playTime = 7530.4, savedAt = now - 300,
		character = { base = "custom", hair = "afro", hat = "cap", name = "  Pavel ", skin = "nope" },
	}
	local s = SaveSlotRules.summary(1, saved)
	check("a save of today: not empty, its slot", not s.empty and s.slot == 1)
	check("…the warehouse's level and name (upgrade 2: level 3, the Storehouse)", s.level == 3 and s.levelName == Config.Warehouse.Levels[3].name, `{s.level} {s.levelName}`)
	check("…the money whole, the pieces, the moves", s.money == 12400 and s.pieces == 2 and s.moves == 7, `{s.money} {s.pieces} {s.moves}`)
	check("…the time played and when it was saved", s.played == 7530 and s.savedAt == now - 300)
	check("…its courier's name trimmed, its look checked", s.name == "Pavel" and s.look ~= nil and (s.look :: any).hair == "afro"
		and (s.look :: any).skin == Config.Characters.Default.skin)
	local old = SaveSlotRules.summary(1, { money = 900, sandboxUpgradesKept = true, sandboxUpgrades = {} })
	check("a save from before 8.3 (no level's flag): the Big Warehouse, level 4", old.level == 4 and old.levelName == Config.Warehouse.Levels[4].name, old.level)
	check("…no courier (its own avatar), no time, never saved with a date", old.name == nil and old.look == nil and old.played == 0 and old.savedAt == nil)
	local junk = SaveSlotRules.summary(3, { money = 50, collection = "x", sandboxUpgrades = 5, playTime = -4, savedAt = 0 / 0, character = "me", sandboxMoves = math.huge })
	check("junk in a save: still a summary (nothing negative, NaN or huge)", not junk.empty and junk.pieces == 0 and junk.played == 0 and junk.savedAt == nil
		and junk.moves >= 0 and junk.moves < 1e6 and junk.look == nil)
	check("latest: the one saved last", SaveSlotRules.latest({ s, old, empty, SaveSlotRules.summary(2, { money = 1, savedAt = now }) }) == 2)
	check("…a save never dated still beats an empty slot", SaveSlotRules.latest({ empty, old }) == 1)
	check("…all empty: none", SaveSlotRules.latest({ empty, SaveSlotRules.summary(3, nil) }) == nil)
end

-- ── The cards' words ───────────────────────────────────────────────────────
check("played: under a minute nothing, minutes, hours and minutes", SaveSlotRules.played(59) == "" and SaveSlotRules.played(60) == "1 min"
	and SaveSlotRules.played(3725) == "1 h 02 min" and SaveSlotRules.played(-5) == "", SaveSlotRules.played(3725))
do
	local now = 1760000000
	check("ago: never, just now, minutes, hours, yesterday, days", SaveSlotRules.ago(nil, now) == "" and SaveSlotRules.ago(now - 30, now) == "just now"
		and SaveSlotRules.ago(now - 300, now) == "5 min ago" and SaveSlotRules.ago(now - 7300, now) == "2 h ago"
		and SaveSlotRules.ago(now - 100000, now) == "yesterday" and SaveSlotRules.ago(now - 4 * 86400 - 10, now) == "4 days ago",
		SaveSlotRules.ago(now - 100000, now))
	check("ago: a clock behind the save's (another server's): just now", SaveSlotRules.ago(now + 50, now) == "just now")
end
check("money: $0, $950, $12,400, $1,234,567", SaveSlotRules.money(0) == "$0" and SaveSlotRules.money(950) == "$950" and SaveSlotRules.money(12400) == "$12,400"
	and SaveSlotRules.money(1234567) == "$1,234,567", SaveSlotRules.money(1234567))

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
