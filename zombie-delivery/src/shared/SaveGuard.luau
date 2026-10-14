--!strict
-- 8.3 SAVES: the save's guard (server/PlayerData.luau; Config.Saving). Pure (no Roblox at its top level;
-- tests/saveguard_test.luau). Everything a save writes passes through it on its way to the DataStore: a DataStore
-- refuses a whole write for one value it cannot keep (NaN, a function, a table with holes …), and every later save of
-- that player would fail the same way, so one bad number would cost everything played since the last good save.
--
--   SaveGuard.clean(value)          a copy a DataStore keeps (JSON) → the copy, what it mended ({ "path: what" }, the
--                                   first Problems of them) and the copy's size as JSON (bytes: an estimate a little
--                                   over the real one; a DataStore key holds 4 MB). It mends: NaN → 0, ±inf → ±Big; a
--                                   string or a key that is no UTF-8, a function, an Instance or any other userdata
--                                   dropped; an array's holes packed (its order kept); a table with string and number
--                                   keys keeps its bigger part; a table inside itself or deeper than Depth dropped.
--                                   Whole numbers, valid strings, booleans and plain tables come back the same.
--   SaveGuard.unknown(saved, known) the top-level keys of a loaded save this version does not know (known: key → true)
--                                   with their values: what a newer server wrote. PlayerData writes them back with
--                                   every save, so a round trip through this server loses none of a newer one's fields
--   SaveGuard.merge(data, extras)   extras' keys that data does not have, put into it (→ how many)
--   SaveGuard.keys(t)               { [key] = true } for a table's string keys
--   SaveGuard.probe()               a stand-in profile with every field set (a field read gives the stand-in back, so a
--                                   field of a field too): the save built from it has every key this version writes,
--                                   the optional ones (nil in a real profile) included
--   SaveGuard.backoff(try, tune)    s to wait after the try-th failed try: tune.First × 2^(try − 1), at most tune.Most

local SaveGuard = {}

SaveGuard.Big = 2 ^ 53 -- ±inf is written as ±this
SaveGuard.Depth = 32 -- tables deeper than this are dropped (a save is 4 – 5 deep)
SaveGuard.Problems = 12 -- mended values listed at most (all are counted)

type State = { problems: { string }, count: number, path: { [any]: boolean } }

local function note(state: State, path: string, what: string)
	state.count += 1
	if #state.problems < SaveGuard.Problems then
		table.insert(state.problems, `{path}: {what}`)
	end
end

local function whole(n: number): boolean
	return n == math.floor(n) and math.abs(n) < SaveGuard.Big
end

-- JSON's length of a number: a whole one as its digits, any other as the longest "%.17g" can write (an estimate on
-- the safe side: 0.5 counts 24).
local function numberSize(n: number): number
	return if whole(n) then #string.format("%d", n) else 24
end

-- JSON's length of a string: its bytes, the quotes and the escapes (a quote or a backslash two bytes, a control
-- character up to six); a byte of a character past ASCII counts three (written as \uXXXX it would take that much).
local function stringSize(s: string): number
	local _, short = string.gsub(s, '["\\]', "")
	local _, control = string.gsub(s, "%c", "")
	local _, wide = string.gsub(s, "[\128-\255]", "")
	return #s + 2 + short + control * 5 + wide * 2
end

local copy: (value: any, path: string, depth: number, state: State) -> (any, number)

-- The entries of `value` under the keys in `keys` (in that order) as an array: what clean keeps of them.
local function asArray(value: any, keys: { any }, path: string, depth: number, state: State): ({ any }, number)
	local out = {}
	local size = 2
	for _, key in keys do
		local item, bytes = copy(value[key], `{path}[{key}]`, depth + 1, state)
		if item ~= nil then
			table.insert(out, item)
			size += bytes + (if #out > 1 then 1 else 0)
		end
	end
	return out, size
end

-- The entries of `value` under string keys as an object: what clean keeps of them.
local function asObject(value: any, path: string, depth: number, state: State): ({ [string]: any }, number)
	local out = {}
	local size = 2
	local n = 0
	for key, raw in next, value do
		if type(key) ~= "string" then
			continue
		end
		if utf8.len(key) == nil then
			note(state, path, "a key that is no UTF-8: dropped")
			continue
		end
		local item, bytes = copy(raw, `{path}.{key}`, depth + 1, state)
		if item ~= nil then
			out[key] = item
			n += 1
			size += stringSize(key) + 1 + bytes + (if n > 1 then 1 else 0)
		end
	end
	return out, size
end

copy = function(value: any, path: string, depth: number, state: State): (any, number)
	local kind = type(value)
	if kind == "boolean" then
		return value, if value then 4 else 5
	elseif kind == "number" then
		if value ~= value then
			note(state, path, "NaN → 0")
			return 0, 1
		elseif value == math.huge or value == -math.huge then
			local big = if value > 0 then SaveGuard.Big else -SaveGuard.Big
			note(state, path, `{value} → {big}`)
			return big, numberSize(big)
		end
		return value, numberSize(value)
	elseif kind == "string" then
		if utf8.len(value) == nil then
			note(state, path, "a string that is no UTF-8: dropped")
			return nil, 0
		end
		return value, stringSize(value)
	elseif kind ~= "table" then
		note(state, path, `a {kind}: dropped`)
		return nil, 0
	end
	if state.path[value] then
		note(state, path, "a table inside itself: dropped")
		return nil, 0
	elseif depth >= SaveGuard.Depth then
		note(state, path, "too deep: dropped")
		return nil, 0
	end
	local count, strings, numbers, most = 0, 0, 0, 0
	for key in next, value do
		count += 1
		if type(key) == "string" then
			strings += 1
		elseif type(key) == "number" and key >= 1 and whole(key) then
			numbers += 1
			most = math.max(most, key)
		end
	end
	state.path[value] = true
	local out: any, size: number
	if strings == count then -- an object (or the empty table)
		out, size = asObject(value, path, depth, state)
	else
		if strings + numbers < count then
			note(state, path, `{count - strings - numbers} key(s) that are neither a name nor 1, 2, 3 …: dropped`)
		end
		if numbers > 0 and numbers >= strings then -- an array (its holes packed, the string keys dropped)
			local keys: { number } = {}
			if most == numbers then
				for index = 1, most do
					keys[index] = index
				end
			else
				for key in next, value do
					if type(key) == "number" and key >= 1 and whole(key) then
						table.insert(keys, key)
					end
				end
				table.sort(keys)
				note(state, path, `an array with holes: packed ({numbers} of {most})`)
			end
			if strings > 0 then
				note(state, path, `a table of {numbers} numbered and {strings} named entries: the named dropped`)
			end
			out, size = asArray(value, keys, path, depth, state)
		else -- an object with some numbered entries: they are dropped
			if numbers > 0 then
				note(state, path, `a table of {strings} named and {numbers} numbered entries: the numbered dropped`)
			end
			out, size = asObject(value, path, depth, state)
		end
	end
	state.path[value] = nil
	return out, size
end

function SaveGuard.clean(value: any): (any, { string }, number)
	local state: State = { problems = {}, count = 0, path = {} }
	local out, size = copy(value, "save", 0, state)
	if state.count > #state.problems then
		table.insert(state.problems, `… {state.count - #state.problems} more`)
	end
	return out, state.problems, size
end

function SaveGuard.unknown(saved: any, known: { [string]: boolean }): { [string]: any }
	local out: { [string]: any } = {}
	if type(saved) ~= "table" then
		return out
	end
	for key, value in next, saved do
		if type(key) == "string" and not known[key] then
			out[key] = value
		end
	end
	return out
end

function SaveGuard.merge(data: { [string]: any }, extras: { [string]: any }): number
	local n = 0
	for key, value in extras do
		if data[key] == nil then
			data[key] = value
			n += 1
		end
	end
	return n
end

function SaveGuard.keys(t: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if type(t) == "table" then
		for key in next, t do
			if type(key) == "string" then
				out[key] = true
			end
		end
	end
	return out
end

function SaveGuard.probe(): any
	local probe: any = {}
	setmetatable(probe, {
		__index = function(): any
			return probe
		end,
	})
	return probe
end

function SaveGuard.backoff(try: number, tune: { First: number, Most: number }): number
	return math.min(tune.Most, tune.First * 2 ^ math.max(0, try - 1))
end

return SaveGuard
