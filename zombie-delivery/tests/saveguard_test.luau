-- 8.3 SAVES: the save's guard (shared/SaveGuard.luau). clean: a plain save comes back the same (a copy, nothing
-- mended, its size as JSON exact for whole numbers and plain strings, never under the real one); NaN, ±inf, a function,
-- a thread, a buffer, a string or a key that is no UTF-8, an array's holes, a mixed table (the bigger part kept), keys
-- that are neither names nor 1, 2, 3, a table inside itself and one too deep: each mended with its path named (the
-- list capped, all counted), the rest kept. unknown / merge / keys / probe (a save built from the stand-in has every
-- key, the optional ones too) and the backoff (1, 2, 4, 4 s).
-- Run: python3 tests/run_tests.py [path to the luau binary]

local SaveGuard = require("./SaveGuard")
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
local function has(problems: { string }, text: string): boolean
	for _, p in problems do
		if string.find(p, text, 1, true) then
			return true
		end
	end
	return false
end

-- A JSON writer as Roblox's DataStore would write (a whole number as its digits, any other "%.17g"; the escapes, a
-- control character as \u00XX): what the size estimate is held against.
local function json(value: any): string
	local kind = type(value)
	if kind == "boolean" then
		return tostring(value)
	elseif kind == "number" then
		return if value == math.floor(value) and math.abs(value) < 2 ^ 53 then string.format("%d", value) else string.format("%.17g", value)
	elseif kind == "string" then
		return '"' .. string.gsub(value, '[%c"\\]', function(c: string): string
			return if c == '"' then '\\"' elseif c == "\\" then "\\\\" else string.format("\\u%04x", string.byte(c))
		end) .. '"'
	end
	local parts = {}
	if #value > 0 or next(value) == nil then
		for _, item in value do
			table.insert(parts, json(item))
		end
		return "[" .. table.concat(parts, ",") .. "]"
	end
	for key, item in value do
		table.insert(parts, json(key) .. ":" .. json(item))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

-- ── clean: a good save comes back the same ────────────────────────────────
local good = {
	money = 12345,
	flag = true,
	off = false,
	name = "Ann's \"best\" van",
	cars = { sprinter = true },
	collection = { entries = { { uid = "101-1", item = "sofa", variant = 3, condition = 0.875, stand = 2, got = 1760000000 }, { uid = "101-2", item = "tv", variant = 1, condition = 1, got = 1760000100 } }, nextUid = 3 },
	empty = {},
	list = { 1, 2, 3 },
	nested = { a = { b = { c = { d = "deep enough" } } } },
}
local out, problems, size = SaveGuard.clean(good)
check("a good save: the same values, nothing mended", same(out, good) and #problems == 0, problems[1])
check("… a copy (not the same tables)", out ~= good and out.collection ~= good.collection and out.collection.entries[1] ~= good.collection.entries[1])
check("… its size never under the JSON's", size >= #json(out), `{size} < {#json(out)}`)
local plain = { money = 500, cars = { sprinter = true, van = false }, ids = { "a", "b", "c" }, n = { 1, 22, 333 }, label = "x\"y\\z" }
local _, _, plainSize = SaveGuard.clean(plain)
check("whole numbers, strings (with escapes), booleans, arrays and objects: the size exact", plainSize == #json(plain), `{plainSize} vs {#json(plain)}`)
check("nil and a lone value: as they are", SaveGuard.clean(nil) == nil and SaveGuard.clean(5) == 5 and SaveGuard.clean("x") == "x")

-- ── clean: what a DataStore cannot keep is mended ──────────────────────────
local bad: any = {
	money = 0 / 0,
	big = math.huge,
	low = -math.huge,
	fn = function() end,
	co = coroutine.create(function() end),
	buf = buffer.create(4),
	broken = "\255\254",
	[("\255key")] = 1,
	holes = { [1] = "a", [3] = "c", [7] = "g" },
	mixedArray = { 10, 20, 30, note = "x" },
	mixedObject = { a = 1, b = 2, c = 3, [1] = "one" },
	odd = { [0.5] = 1, [true] = 2, [-1] = 3, keep = 4 },
	deep = { entries = { { condition = 0 / 0, uid = "a" }, { condition = 0.5, uid = "b" } } },
}
local loop: any = { name = "loop" }
loop.self = loop
bad.loop = loop
local nest: any = { level = 0 }
local at = nest
for level = 1, 40 do
	at.next = { level = level }
	at = at.next
end
bad.nest = nest
local cap = SaveGuard.Problems
SaveGuard.Problems = 100 -- (every problem listed here: the cap is checked below)
local mended, why = SaveGuard.clean(bad)
SaveGuard.Problems = cap
check("NaN → 0", mended.money == 0 and has(why, "save.money: NaN → 0"), why[1])
check("±inf → ±2^53", mended.big == 2 ^ 53 and mended.low == -2 ^ 53 and has(why, "save.big") and has(why, "save.low"))
check("a function, a thread, a buffer: dropped", mended.fn == nil and mended.co == nil and mended.buf == nil and has(why, "save.fn: a function") and has(why, "save.co: a thread") and has(why, "save.buf: a buffer"))
check("a string that is no UTF-8: dropped", mended.broken == nil and has(why, "save.broken: a string that is no UTF-8"))
check("a key that is no UTF-8: dropped", mended["\255key"] == nil and has(why, "a key that is no UTF-8"))
check("an array's holes packed, its order kept", same(mended.holes, { "a", "c", "g" }) and has(why, "save.holes: an array with holes"))
check("a mixed table, mostly numbered: the array kept, the named entry dropped", same(mended.mixedArray, { 10, 20, 30 }) and has(why, "save.mixedArray: a table of 3 numbered and 1 named"))
check("a mixed table, mostly named: the object kept, the numbered entry dropped", same(mended.mixedObject, { a = 1, b = 2, c = 3 }) and has(why, "save.mixedObject: a table of 3 named and 1 numbered"))
check("keys that are neither names nor 1, 2, 3 (0.5, true, -1): dropped", same(mended.odd, { keep = 4 }) and has(why, "save.odd: 3 key(s)"))
check("a NaN deep inside: 0 there, its neighbours kept", mended.deep.entries[1].condition == 0 and mended.deep.entries[1].uid == "a" and mended.deep.entries[2].condition == 0.5)
check("a table inside itself: that one dropped, the rest kept", mended.loop.name == "loop" and mended.loop.self == nil)
local depth, node = 0, mended.nest
while node do
	depth += 1
	node = node.next
end
check("a table too deep: cut at SaveGuard.Depth", depth == SaveGuard.Depth - 1, depth)
local many = {}
for i = 1, 40 do
	many[`k{i}`] = 0 / 0
end
local _, capped = SaveGuard.clean(many)
check("the list of what was mended is capped, all counted (… N more)", #capped == SaveGuard.Problems + 1 and has(capped, `… {40 - SaveGuard.Problems} more`), #capped)
local shared = { 1, 2 }
local twice, twiceWhy = SaveGuard.clean({ a = shared, b = shared })
check("one table under two keys (no loop): kept in both, nothing mended", same(twice, { a = { 1, 2 }, b = { 1, 2 } }) and #twiceWhy == 0)

-- ── unknown, merge, keys ───────────────────────────────────────────────────
local known = { money = true, lock = true, bike = true }
local saved = { money = 5, lock = { job = "x" }, futureField = { level = 3 }, futureKept = true, [1] = "junk" }
local unknown = SaveGuard.unknown(saved, known)
check("unknown: the keys this version does not know, with their values (no number keys)", same(unknown, { futureField = { level = 3 }, futureKept = true }))
check("… a save that is no table: none", next(SaveGuard.unknown(nil, known)) == nil and next(SaveGuard.unknown("x", known)) == nil)
local data = { money = 9, futureKept = false }
local put = SaveGuard.merge(data, unknown)
check("merge: only the keys the data does not have", put == 1 and data.futureKept == false and same(data.futureField, { level = 3 }) and data.money == 9)
check("keys: a table's string keys", same(SaveGuard.keys({ a = 1, b = false, [1] = 2 }), { a = true, b = true }) and next(SaveGuard.keys(nil)) == nil)

-- ── probe ──────────────────────────────────────────────────────────────────
local probe = SaveGuard.probe()
check("probe: every field set (a field of a field too)", probe.money ~= nil and probe.bike ~= nil and probe.collection.entries ~= nil)
local built = (function(profile: any, lock: any): any
	return { money = profile.money, bike = profile.bike, title = profile.title, flag = true, lock = lock }
end)(probe, {})
check("… a save built from it has every key (the optional ones, the lock)", same(SaveGuard.keys(built), { money = true, bike = true, title = true, flag = true, lock = true }))

-- ── backoff ────────────────────────────────────────────────────────────────
local B = Config.Saving.Backoff
check("backoff: 1, 2, 4, 4 s (First × 2^(try − 1), at most Most)", SaveGuard.backoff(1, B) == 1 and SaveGuard.backoff(2, B) == 2 and SaveGuard.backoff(3, B) == 4 and SaveGuard.backoff(4, B) == 4)
check("Config.Saving: sane numbers", Config.Saving.Soon > 0 and Config.Saving.Gap >= 6 and Config.Saving.FinalTries >= Config.Saving.Tries and Config.Saving.CloseWait < 30
	and Config.Saving.MaxBytes < 4 * 1024 * 1024 and Config.Saving.WarnBytes < Config.Saving.MaxBytes and Config.Saving.Call > 0 and Config.Saving.LeaveWait > 0)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
