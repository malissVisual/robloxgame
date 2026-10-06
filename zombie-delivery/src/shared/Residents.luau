--!strict
-- 5.5, people in every building: who lives in a home (Map.Homes), made up from Config.Residents the same way every
-- time (seeded by the home's id: the same in every server, the client and the tests). Pure Luau (Config, Map), used by
-- shared/Deliveries.luau (a delivery to a home goes to one of its residents) and tested in tests/residents_test.luau.
-- Nobody is built in the world: a resident only steps out when you knock (server/Cargo.luau, the look from the name).
--
--   An apartment building   `floors` × 4 flats ("1A" … "9D"), FlatPeople (1 – 2) in each: one household, its surname.
--   A Suburbs house         HousePeople (1 – 4): one family, one surname.
-- A household is Czech ("Jana Nováková", "Petr Novák") or English ("Mike Brown"); now and then a member has a first
-- name from the other list, a few are known by a nickname only ("Old Pete"). No two residents of a home share a name.
--
--   Residents.of(home)            its residents, { { name, flat? } } (flat: an apartment's "4C"; the same table every call)
--   Residents.count(home)         how many live there
--   Residents.pick(home, r)       one of them by chance (r: () -> number in [0, 1))
--   Residents.weight(home)        its weight in the deliveries' draw: its count, at most Config.Residents.MaxWeight
--   Residents.place(home, flat)   where a delivery goes: "Apt 4C, 40 6th Ave" (an apartment's flat), else the address
--   Residents.person(resident)    the receiver at a stop (Config.PersonDef: title "Apt 4C" / "Resident", a townsperson)
--   Residents.caps(text)          string.upper that keeps the Czech letters ("NOVÁKOVÁ", not "NOVáKOVá")

local Config = require(script.Parent.Config)
local Map = require(script.Parent.Map)

local Residents = {}

export type Resident = { name: string, flat: string? }

type Origin = { Women: { string }, Men: { string }, Surnames: { { string } } }

local cache: { [string]: { Resident } } = {}

-- A home's id as a seed (the same number everywhere).
local function hash(text: string): number
	local h = 17
	for n = 1, #text do
		h = (h * 131 + string.byte(text, n)) % 2147483629
	end
	return h
end

local function between(r: () -> number, range: { number }): number
	local low, high = range[1], range[2] or range[1]
	return math.clamp(low + math.floor(r() * (high - low + 1)), low, high)
end

local function one<T>(r: () -> number, list: { T }): T
	return list[math.clamp(math.floor(r() * #list) + 1, 1, #list)]
end

-- The people of one household: `count` of them, one surname (a man's or a woman's form), the names not in `taken`.
local function household(r: () -> number, count: number, flat: string?, taken: { [string]: boolean }, out: { Resident })
	local tuning = Config.Residents
	local czech = r() < 0.5
	local origin: Origin = if czech then tuning.Czech else tuning.English
	local other: Origin = if czech then tuning.English else tuning.Czech
	local surname = one(r, origin.Surnames)
	for _ = 1, count do
		local name = ""
		for _ = 1, 12 do
			if r() < tuning.NicknameChance then
				name = one(r, tuning.Nicknames)
			else
				local woman = r() < 0.5
				local from = if r() < tuning.OtherOrigin then other else origin
				local first = one(r, if woman then from.Women else from.Men)
				name = `{first} {if woman then surname[2] or surname[1] else surname[1]}`
			end
			if not taken[name] then
				break
			end
			name = ""
		end
		if name ~= "" then
			taken[name] = true
			table.insert(out, { name = name, flat = flat })
		end
	end
end

function Residents.of(home: Map.Home): { Resident }
	local known = cache[home.id]
	if known then
		return known
	end
	local tuning = Config.Residents
	local r = Map.lcg(hash(home.id))
	r() -- (the first number follows the seed too closely)
	local out: { Resident } = {}
	local taken: { [string]: boolean } = {}
	if home.kind == "apartment" then
		for floor = 1, home.floors or 2 do
			for letter = 0, 3 do
				household(r, between(r, tuning.FlatPeople), `{floor}{string.char(65 + letter)}`, taken, out)
			end
		end
	else
		household(r, between(r, tuning.HousePeople), nil, taken, out)
	end
	if #out == 0 then
		-- (only when every name was taken: never with the real lists, but a home always has somebody)
		table.insert(out, { name = `Resident of {home.address}`, flat = nil })
	end
	cache[home.id] = out
	return out
end

function Residents.count(home: Map.Home): number
	return #Residents.of(home)
end

function Residents.pick(home: Map.Home, r: () -> number): Resident
	return one(r, Residents.of(home))
end

function Residents.weight(home: Map.Home): number
	return math.clamp(Residents.count(home), 1, math.max(1, Config.Residents.MaxWeight))
end

function Residents.place(home: Map.Home, flat: string?): string
	return if flat and home.kind == "apartment" then `Apt {flat}, {home.address}` else home.name
end

function Residents.person(resident: Resident): Config.PersonDef
	return { name = resident.name, title = if resident.flat then `Apt {resident.flat}` else "Resident", role = "townsperson" }
end

-- The small letters with a hacek or an accent and their capitals (UTF-8): Czech, plus the few that come along.
local CAPS: { [string]: string } = {
	["á"] = "Á", ["č"] = "Č", ["ď"] = "Ď", ["é"] = "É", ["ě"] = "Ě", ["í"] = "Í", ["ň"] = "Ň", ["ó"] = "Ó",
	["ř"] = "Ř", ["š"] = "Š", ["ť"] = "Ť", ["ú"] = "Ú", ["ů"] = "Ů", ["ý"] = "Ý", ["ž"] = "Ž",
	["ä"] = "Ä", ["ö"] = "Ö", ["ü"] = "Ü", ["ñ"] = "Ñ", ["ç"] = "Ç", ["è"] = "È", ["à"] = "À",
}

function Residents.caps(text: string): string
	local upper = string.upper(text)
	if not string.find(upper, "[\128-\255]") then
		return upper
	end
	return (string.gsub(upper, "[\192-\255][\128-\191]*", function(char: string): string
		return CAPS[char] or char
	end))
end

return Residents
