-- Logic test of 5.5, people in every building (shared/Residents.luau, Config.Residents, shared/Deliveries.luau): every
-- home has residents, the same every time; an apartment building floors × 4 flats with 1 – 2 people each, a house
-- 1 – 4 of one family; the names come from the lists, unique in a home; the weight is capped; a delivery to a home
-- names a resident (an apartment's flat in the address and the title); the caps keep the Czech letters.
-- Standalone Luau CLI. Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Map = require("./Map")
local Residents = require("./Residents")
local Deliveries = require("./Deliveries")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local function dice(seed: number): () -> number
	local state = seed
	return function(): number
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end

local tuning = Config.Residents

-- The lists ----------------------------------------------------------------------------------------

local firsts, surnames = 0, 0
local listsOk = true
for _, origin in { tuning.Czech, tuning.English } do
	firsts += #origin.Women + #origin.Men
	surnames += #origin.Surnames
	for _, pair in origin.Surnames do
		if #pair < 1 or #pair > 2 then
			listsOk = false
		end
	end
end
check("about 40 first names and 40 surnames", firsts >= 36 and surnames >= 36, `{firsts} / {surnames}`)
check("every surname a man's form (and maybe a woman's)", listsOk)
check("a Czech woman's surname is the -ová / -á form", tuning.Czech.Surnames[1][2] == "Nováková")
check("a few nicknames (the end of the world)", table.find(tuning.Nicknames, "Old Pete") ~= nil and table.find(tuning.Nicknames, "Doc Hansen") ~= nil)
check("the numbers", tuning.FlatPeople[1] == 1 and tuning.FlatPeople[2] == 2 and tuning.HousePeople[1] == 1 and tuning.HousePeople[2] == 4 and tuning.MaxWeight >= 2)

-- Who lives where ----------------------------------------------------------------------------------

local known: { [string]: boolean } = {}
for _, origin in { tuning.Czech, tuning.English } do
	for _, first in origin.Women do
		for _, pair in tuning.Czech.Surnames do
			known[`{first} {pair[2] or pair[1]}`] = true
		end
		for _, pair in tuning.English.Surnames do
			known[`{first} {pair[2] or pair[1]}`] = true
		end
	end
	for _, first in origin.Men do
		for _, pair in tuning.Czech.Surnames do
			known[`{first} {pair[1]}`] = true
		end
		for _, pair in tuning.English.Surnames do
			known[`{first} {pair[1]}`] = true
		end
	end
end
for _, nickname in tuning.Nicknames do
	known[nickname] = true
end

local problem: string? = nil
local total, flats, apartments, houses, nicknames = 0, 0, 0, 0, 0
local largest = 0
local czech, english = 0, 0
for _, home in Map.Homes do
	local people = Residents.of(home)
	if people ~= Residents.of(home) then
		problem = `{home.id}: a new list every call`
	end
	if Residents.count(home) ~= #people then
		problem = `{home.id}: count`
	end
	total += #people
	largest = math.max(largest, #people)
	local names: { [string]: boolean } = {}
	for _, person in people do
		if names[person.name] then
			problem = `{home.id}: {person.name} twice`
		end
		names[person.name] = true
		if not known[person.name] then
			problem = `{home.id}: {person.name} is not from the lists`
		end
		if table.find(tuning.Nicknames, person.name) then
			nicknames += 1
		elseif string.find(person.name, "[\128-\255]") then
			czech += 1
		else
			english += 1
		end
	end
	if home.kind == "apartment" then
		apartments += 1
		local perFlat: { [string]: number } = {}
		for _, person in people do
			local flat = person.flat
			if not flat or not string.match(flat, "^%d+[A-D]$") or tonumber(string.match(flat, "^%d+")) > (home.floors or 0) then
				problem = `{home.id}: flat {flat}`
			else
				perFlat[flat] = (perFlat[flat] or 0) + 1
			end
		end
		local count = 0
		for _, n in perFlat do
			count += 1
			if n < 1 or n > 2 then
				problem = `{home.id}: {n} in a flat`
			end
		end
		flats += count
		if count ~= (home.floors or 0) * 4 then
			problem = `{home.id}: {count} flats of {(home.floors or 0) * 4} lived in`
		end
	else
		houses += 1
		if #people < 1 or #people > 4 then
			problem = `{home.id}: {#people} people in a house`
		end
		local family: string? = nil
		for _, person in people do
			if person.flat ~= nil then
				problem = `{home.id}: a flat in a house`
			end
			if not table.find(tuning.Nicknames, person.name) then
				-- one family: the same surname (a man's or a woman's form of it)
				local last = string.match(person.name, "(%S+)$") or ""
				local stem = string.sub(last, 1, 4)
				if family and family ~= stem then
					problem = `{home.id}: two families ({family}, {stem})`
				end
				family = stem
			end
		end
	end
end
check("every home's residents: the same list every call, unique names from the lists", problem == nil, problem)
print(`  {total} residents in {#Map.Homes} homes ({apartments} buildings, {flats} flats; {houses} houses), {largest} at most in one; {czech} Czech, {english} English, {nicknames} nicknames`)
check("every flat lived in (1 – 2 each), a house 1 – 4 of one family", problem == nil)
check("a big building has many residents", largest >= 20, largest)
check("both Czech and English names, a few nicknames", czech > total / 5 and english > total / 5 and nicknames > 0 and nicknames < total / 10, `{czech} / {english} / {nicknames}`)

-- Seeded by the home's id, not by the order of the calls: a fresh copy of a home (Map.makeLots) has the same people.
local last = Map.Homes[#Map.Homes]
local _, fresh = Map.makeLots()
local twin = fresh[#fresh]
local sameNames = twin.id == last.id and Residents.count(twin) == Residents.count(last)
for n, person in Residents.of(twin) do
	sameNames = sameNames and person.name == Residents.of(last)[n].name and person.flat == Residents.of(last)[n].flat
end
check("seeded by the home: a fresh copy of the home has the same people", sameNames)

-- pick, weight, place, person ------------------------------------------------------------------------

local tower: Map.Home? = nil
local house: Map.Home? = nil
for _, home in Map.Homes do
	if home.kind == "apartment" and (not tower or (home.floors or 0) > ((tower :: Map.Home).floors or 0)) then
		tower = home
	elseif home.kind == "house" and not house then
		house = home
	end
end
local big, small = tower :: Map.Home, house :: Map.Home
local r = dice(5)
local seen: { [string]: boolean } = {}
local pickOk = true
for _ = 1, 200 do
	local person = Residents.pick(big, r)
	pickOk = pickOk and table.find(Residents.of(big), person) ~= nil
	seen[person.name] = true
end
local distinct = 0
for _ in seen do
	distinct += 1
end
check("pick: one of the residents, many different ones in a big building", pickOk and distinct >= 20, distinct)
check("weight: the residents, capped", Residents.weight(big) == tuning.MaxWeight and Residents.weight(small) == math.min(Residents.count(small), tuning.MaxWeight))
local flat = Residents.of(big)[1].flat
check("place: an apartment's flat and its address", Residents.place(big, flat) == `Apt {flat}, {big.address}` and Residents.place(small, nil) == small.name)
local someone = Residents.person(Residents.of(big)[1])
check("person: the name, the flat as the title, a townsperson", someone.name == Residents.of(big)[1].name and someone.title == `Apt {flat}` and someone.role == "townsperson")
check("person: a house's resident", Residents.person(Residents.of(small)[1]).title == "Resident")
check("caps keep the Czech letters", Residents.caps("Jana Nováková, Apt 4C") == "JANA NOVÁKOVÁ, APT 4C" and Residents.caps("Jiří Dvořák · Růžičková") == "JIŘÍ DVOŘÁK · RŮŽIČKOVÁ" and Residents.caps("Mike Brown") == "MIKE BROWN")

-- The deliveries -------------------------------------------------------------------------------------

local byId: { [string]: Config.BusinessDef } = {}
for _, business in Config.Jobs.Businesses do
	byId[business.id] = business
end
local pizzeria = byId.pizzeria
local entries: { [Map.Home]: number } = {}
local targetsOk = true
for _, target in Deliveries.targets(pizzeria) do
	if target.home then
		local home = target.home
		entries[home] = (entries[home] or 0) + 1
		local spot = Deliveries.spotOf(target.address)
		if not target.person or not spot or spot.home ~= home or target.address.x ~= home.park.x or target.address.z ~= home.park.z then
			targetsOk = false
		end
		if home.kind == "apartment" and not string.match(target.address.name, "^Apt %d+[A-D], " .. home.address .. "$") then
			targetsOk = false
		end
	end
end
local weightOk = true
for home, n in entries do
	weightOk = weightOk and n == Residents.weight(home)
end
check("targets: a home's entries are its residents (the flat's address, the building's spot)", targetsOk)
check("targets: a home as often as its weight (a tower more often than a house)", weightOk and entries[big] == tuning.MaxWeight)
check("flatAddress: the same table every call; a house's is its own address", Deliveries.flatAddress(big, "1A") == Deliveries.flatAddress(big, "1A")
	and Deliveries.flatAddress(small, nil) == Deliveries.homeAddress(small) and Deliveries.flatAddress(big, "1A") ~= Deliveries.homeAddress(big))

local rr = dice(9)
local namedOk, flatOk, avoidOk = true, true, true
local towers, homesSeen = 0, 0
for _ = 1, 60 do
	local target = Deliveries.dropFor(pizzeria, big.park.x, big.park.z, 50, 900, {}, rr, nil)
	if target and target.home then
		homesSeen += 1
		local home = target.home
		local person = target.person
		if not person or not Residents.of(home) then
			namedOk = false
		else
			local lives = false
			for _, resident in Residents.of(home) do
				lives = lives or resident.name == person.name
			end
			namedOk = namedOk and lives
		end
		if home.kind == "apartment" then
			towers += 1
			flatOk = flatOk and person ~= nil and person.title ~= nil and string.find(target.address.name, person.title :: string, 1, true) == 1
		end
		-- the next drop never in the same building (another flat of it neither)
		local other = Deliveries.dropFor(pizzeria, big.park.x, big.park.z, 0, 900, { target.address }, rr, nil)
		avoidOk = avoidOk and (other == nil or other.home ~= home)
	end
end
check("dropFor: a home's drop names somebody who lives there", homesSeen > 0 and namedOk)
check("dropFor: an apartment's drop is the person's flat ('Apt 4C, …')", towers > 0 and flatOk, towers)
check("dropFor: a home to avoid is avoided whole", avoidOk)
local bakery = byId.bakery
local b2b = true
for _, target in Deliveries.targets(bakery) do
	if target.kind == "venue" then
		b2b = b2b and target.home == nil and target.person ~= nil and (target.person :: Config.PersonDef).role ~= "townsperson"
	end
end
check("B2B keeps the storefront's own person", b2b)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
