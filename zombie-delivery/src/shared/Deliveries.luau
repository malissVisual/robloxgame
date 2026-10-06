--!strict
-- 5.3, real places for the deliveries: where an order comes from and where it goes. Pure Luau (Map + Config), used by
-- server/Jobs.luau (the board's offers, the stops' spots) and tested in tests/deliveries_test.luau.
--
-- A business with a storefront (Map.Venues, Map.venuesOf) sends from there: the pick-up's circle is the venue's park
-- (on the road at the curb in front), its pile just outside the door, its cook / clerk in the doorway (Map's clerk
-- spot). The drop is one of the business's `to` (Config.Jobs.Businesses): a home's door (Map.Homes: a Suburbs house, a
-- downtown apartment entrance), another storefront (B2B: its own person takes it) or the Harbor. The hours and the
-- evening peak of every business are here too, and the newspaper round's doors (Config.Jobs.Round).
-- 5.5: every Downtown tower that faces a street is an apartment building, and a home's delivery goes to one of its
-- residents (shared/Residents.luau): the person is the resident ("Jana Nováková", title "Apt 4C"), an apartment's
-- address is the flat's ("Apt 4C, 40 6th Ave": the building's spot, door and park). A home weighs Residents.weight in
-- the draw (its residents, capped: a tower comes up more often than a house); B2B and the Harbor keep their people.
--
--   Deliveries.inHours(range, hour)       is the game clock `hour` inside { from, to } (over midnight when from > to)?
--   Deliveries.open(business, hour)       does the business send anything now (its `hours`)?
--   Deliveries.peak(business, hour)       the pay multiplier of its evening peak now (1 outside it)
--   Deliveries.street(venue)              the street its front faces ("Ash St")
--   Deliveries.venueAddress(venue)        a Map.Address for the venue (its park; the same table every call)
--   Deliveries.homeAddress(home)          … for a home (its park)
--   Deliveries.flatAddress(home, flat)    5.5: … for a flat of an apartment building ("Apt 4C, 40 6th Ave"; its spot is
--                                         the building's; the same table every call); a house's: its homeAddress
--   Deliveries.residentTarget(home, resident)   5.5: the Target of a delivery to that resident (their flat, the person)
--   Deliveries.spotOf(address)            the venue's / home's spot for one of those addresses (nil: an ordinary one)
--   Deliveries.venueFor(business, x, z, reach, allow)   the business's storefront nearest to (x, z) within `reach`
--                                         (manhattan to its park), nil without one; `allow` filters by its address
--   Deliveries.targets(business)          everywhere it delivers to (its `to`), each { address, person?, kind, home? }
--                                         (5.5: a home Residents.weight times, each a resident of it)
--   Deliveries.dropFor(business, x, z, low, high, avoid, r, allow)   one target low … high (manhattan) from (x, z),
--                                         else the closest to that band (nil: the business has no `to`, or nothing);
--                                         5.5: at a home, any of its residents by chance; never a home of `avoid`
--   Deliveries.round(venue, reach, r, allow, budget)   a newspaper round: the doors (in walking order) on one or two
--                                         streets near the print shop (each within `reach` of it, the route from it
--                                         within `budget`) and the papers each takes ({ { home, papers } })
--   Deliveries.reaches(business, x, z, low, high, allow)   does it deliver anywhere low … high from (x, z)?
--   Deliveries.closedNear(x, z, reach, hour, allow)   only shut light-run storefronts within reach (the board's note)

local Config = require(script.Parent.Config)
local Map = require(script.Parent.Map)
local Residents = require(script.Parent.Residents)

local Deliveries = {}

export type Spot = {
	kind: string, -- "venue" | "home"
	pile: Map.Spot,
	park: Map.Spot,
	facing: Map.Spot,
	door: Map.Spot,
	clerk: Map.Spot?, -- a storefront's person stands here (a built one; the older ones: at the pile)
	venue: Map.Venue?,
	home: Map.Home?,
}
export type Target = { address: Map.Address, person: Config.PersonDef?, kind: string, home: Map.Home? }
export type Door = { home: Map.Home, papers: number }

local spots: { [Map.Address]: Spot } = {}
local venueAddresses: { [string]: Map.Address } = {}
local homeAddresses: { [string]: Map.Address } = {}
local flatAddresses: { [string]: Map.Address } = {}

function Deliveries.inHours(range: { number }?, hour: number): boolean
	if not range or #range < 2 then
		return true
	end
	local from, to = range[1], range[2]
	local h = hour % 24
	if from <= to then
		return h >= from and h < to
	end
	return h >= from or h < to
end

function Deliveries.open(business: Config.BusinessDef, hour: number): boolean
	return Deliveries.inHours(business.hours, hour)
end

function Deliveries.peak(business: Config.BusinessDef, hour: number): number
	local peak = business.peak
	if peak and #peak >= 3 and Deliveries.inHours({ peak[1], peak[2] }, hour) then
		return peak[3]
	end
	return 1
end

local function districtOf(id: string): Map.District?
	for _, d in Map.Districts do
		if d.id == id then
			return d
		end
	end
	return nil
end

-- The street a front at (x, z) facing (fx, fz) looks onto (Map.addresses' names).
local function streetAt(d: Map.District, x: number, z: number, fx: number, fz: number): string
	local cell = Config.City.BlockSize + Config.City.RoadWidth
	local i = math.floor((x - d.ox) / cell + 0.5)
	local j = math.floor((z - d.oz) / cell + 0.5)
	if fz ~= 0 then
		local k = j + (if fz > 0 then 0 else -1) - d.j0 + 1
		return d.streets[k % #d.streets + 1]
	end
	local k = i + (if fx > 0 then 0 else -1) - d.i0 + 1
	return d.avenues[k % #d.avenues + 1]
end

function Deliveries.street(venue: Map.Venue): string
	local d = districtOf(venue.district)
	if not d then
		return ""
	end
	return streetAt(d, venue.x, venue.z, venue.facing.x, venue.facing.z)
end

local function districtName(id: string): string
	local d = districtOf(id)
	return if d then d.name else id
end

function Deliveries.venueAddress(venue: Map.Venue): Map.Address
	local known = venueAddresses[venue.id]
	if known then
		return known
	end
	local street = Deliveries.street(venue)
	local address: Map.Address = {
		x = venue.park.x,
		z = venue.park.z,
		nx = venue.facing.x,
		nz = venue.facing.z,
		name = if street ~= "" then `{venue.name}, {street}` else venue.name,
		district = districtName(venue.district),
		poi = false,
	}
	venueAddresses[venue.id] = address
	spots[address] = {
		kind = "venue",
		pile = venue.pile,
		park = venue.park,
		facing = venue.facing,
		door = venue.door,
		clerk = if venue.built then venue.clerk else nil,
		venue = venue,
		home = nil,
	}
	return address
end

function Deliveries.homeAddress(home: Map.Home): Map.Address
	local known = homeAddresses[home.id]
	if known then
		return known
	end
	local address: Map.Address = {
		x = home.park.x,
		z = home.park.z,
		nx = home.facing.x,
		nz = home.facing.z,
		name = home.name,
		district = districtName(home.district),
		poi = false,
	}
	homeAddresses[home.id] = address
	spots[address] = { kind = "home", pile = home.pile, park = home.park, facing = home.facing, door = home.door, clerk = nil, venue = nil, home = home }
	return address
end

function Deliveries.flatAddress(home: Map.Home, flat: string?): Map.Address
	if not flat or home.kind ~= "apartment" then
		return Deliveries.homeAddress(home)
	end
	local key = `{home.id}:{flat}`
	local known = flatAddresses[key]
	if known then
		return known
	end
	local building = Deliveries.homeAddress(home)
	local address: Map.Address = table.clone(building)
	address.name = Residents.place(home, flat)
	flatAddresses[key] = address
	spots[address] = spots[building]
	return address
end

function Deliveries.residentTarget(home: Map.Home, resident: Residents.Resident): Target
	return { address = Deliveries.flatAddress(home, resident.flat), person = Residents.person(resident), kind = home.kind, home = home }
end

function Deliveries.spotOf(address: Map.Address): Spot?
	return spots[address]
end

function Deliveries.venueFor(business: Config.BusinessDef, x: number, z: number, reach: number, allow: ((Map.Address) -> boolean)?): Map.Venue?
	local best: Map.Venue? = nil
	local bestGap = math.huge
	for _, venue in Map.venuesOf(business.id) do
		local gap = Map.manhattan(x, z, venue.park.x, venue.park.z)
		if gap <= reach and gap < bestGap and (not allow or allow(Deliveries.venueAddress(venue))) then
			best, bestGap = venue, gap
		end
	end
	return best
end

local function businessById(id: string): Config.BusinessDef?
	for _, business in Config.Jobs.Businesses do
		if business.id == id then
			return business
		end
	end
	return nil
end

local targetCache: { [string]: { Target } } = {}

function Deliveries.targets(business: Config.BusinessDef): { Target }
	local known = targetCache[business.id]
	if known then
		return known
	end
	local out: { Target } = {}
	local kinds: { string } = business.to or {}
	for _, kind in kinds do
		if kind == "house" or kind == "apartment" then
			for _, home in Map.Homes do
				if home.kind == kind then
					-- 5.5: a home as often as it has residents (capped), each entry one of them (spread over the flats)
					local people = Residents.of(home)
					local weight = Residents.weight(home)
					for n = 1, weight do
						table.insert(out, Deliveries.residentTarget(home, people[math.floor((n - 1) * #people / weight) + 1]))
					end
				end
			end
		elseif kind == "harbor" then
			local foreman = Config.Jobs.PlacePeople.docks
			for _, address in Map.addresses() do
				if not address.poi and address.district == "Harbor" then
					local target: Target = { address = address, person = foreman, kind = "harbor" :: string }
					table.insert(out, target)
				end
			end
		elseif string.sub(kind, 1, 6) == "venue:" then
			local other = businessById(string.sub(kind, 7))
			if other then
				for _, venue in Map.venuesOf(other.id) do
					table.insert(out, { address = Deliveries.venueAddress(venue), person = other.giver, kind = "venue" })
				end
			end
		end
	end
	targetCache[business.id] = out
	return out
end

function Deliveries.dropFor(business: Config.BusinessDef, x: number, z: number, low: number, high: number, avoid: { Map.Address }, r: () -> number, allow: ((Map.Address) -> boolean)?): Target?
	local fits: { Target } = {}
	local closest: Target? = nil
	local closestGap = math.huge
	-- 5.5: a home to avoid is avoided whole (not another flat of the same building)
	local avoidHomes: { [Map.Home]: boolean } = {}
	for _, address in avoid do
		local spot = spots[address]
		if spot and spot.home then
			avoidHomes[spot.home] = true
		end
	end
	for _, target in Deliveries.targets(business) do
		local address = target.address
		if table.find(avoid, address) or (target.home and avoidHomes[target.home]) or (allow and not allow(address)) then
			continue
		end
		local d = Map.manhattan(x, z, address.x, address.z)
		if d >= low and d <= high then
			table.insert(fits, target)
		end
		local gap = if d < low then low - d else d - high
		if gap < closestGap then
			closest, closestGap = target, gap
		end
	end
	local chosen = if #fits > 0 then fits[math.clamp(math.floor(r() * #fits) + 1, 1, #fits)] else closest
	local home = if chosen then chosen.home else nil
	if home then
		-- 5.5: anybody who lives there, not only the ones the draw's entries name
		return Deliveries.residentTarget(home, Residents.pick(home, r))
	end
	return chosen
end

-- 5.3 review: is a storefront of a business that sends light runs (Config.Cargo.LightLooks) within `reach` (manhattan to
-- its park) of (x, z) shut at `hour`, and none of them open there? (The board's ON FOOT note: "Shops nearby are
-- closed".) `allow` filters by the venue's address.
function Deliveries.closedNear(x: number, z: number, reach: number, hour: number, allow: ((Map.Address) -> boolean)?): boolean
	local closed = false
	for _, business in Config.Jobs.Businesses do
		if not Config.Cargo.LightLooks[business.look] then
			continue
		end
		for _, venue in Map.venuesOf(business.id) do
			if Map.manhattan(x, z, venue.park.x, venue.park.z) <= reach and (not allow or allow(Deliveries.venueAddress(venue))) then
				if Deliveries.open(business, hour) then
					return false
				end
				closed = true
			end
		end
	end
	return closed
end

-- ── The newspaper round ────────────────────────────────────────────────────

type Street = { key: string, doors: { Map.Home }, papers: number, near: number }

local function papersAt(home: Map.Home): number
	return if home.kind == "apartment" then math.max(1, Config.Jobs.Round.FlatPapers) else 1
end

local function gapBetween(a: Map.Home, b: Map.Home): number
	return Map.manhattan(a.park.x, a.park.z, b.park.x, b.park.z)
end

function Deliveries.round(venue: Map.Venue, reach: number, r: () -> number, allow: ((Map.Address) -> boolean)?, budget: number?): { Door }
	local tuning = Config.Jobs.Round
	local limit = budget or math.huge
	local byKey: { [string]: Street } = {}
	local streets: { Street } = {}
	for _, home in Map.Homes do
		if allow and not allow(Deliveries.homeAddress(home)) then
			continue
		end
		-- (5.3 review: only the doors within reach of the print shop, not a whole street that starts there)
		local near = Map.manhattan(venue.park.x, venue.park.z, home.park.x, home.park.z)
		if near > reach then
			continue
		end
		local key = `{home.district}:{home.street}`
		local found = byKey[key]
		local street: Street = if found then found else { key = key, doors = {}, papers = 0, near = math.huge }
		if not found then
			byKey[key] = street
			table.insert(streets, street)
		end
		table.insert(street.doors, home)
		street.papers += papersAt(home)
		street.near = math.min(street.near, near)
	end
	table.sort(streets, function(a: Street, b: Street): boolean
		return a.key < b.key
	end)
	if #streets == 0 then
		return {}
	end
	local most = math.max(1, tuning.Streets)
	-- The round that starts on `first`: then the nearest other streets (door to door) while the papers are short of
	-- Papers[1] (Streets of them, one more only when they still are), the doors in walking order (from the shop, always
	-- the nearest door next) while the route stays within `budget` (5.3 review). Its doors and papers.
	local function build(first: Street): ({ Door }, number)
		local chosen: { Street } = { first }
		local papers = first.papers
		while papers < tuning.Papers[1] and #chosen < most + 1 do
			local best: Street? = nil
			local bestGap = math.huge
			for _, street in streets do
				if table.find(chosen, street) then
					continue
				end
				for _, mine in chosen do
					for _, a in mine.doors do
						for _, b in street.doors do
							local gap = gapBetween(a, b)
							if gap < bestGap then
								best, bestGap = street, gap
							end
						end
					end
				end
			end
			if not best then
				break
			end
			table.insert(chosen, best)
			papers += best.papers
		end
		local left: { Map.Home } = {}
		for _, street in chosen do
			for _, home in street.doors do
				table.insert(left, home)
			end
		end
		local out: { Door } = {}
		local x, z = venue.park.x, venue.park.z
		local total, walked = 0, 0
		while #left > 0 do
			local index, bestGap = 1, math.huge
			for n, home in left do
				local gap = Map.manhattan(x, z, home.park.x, home.park.z)
				if gap < bestGap then
					index, bestGap = n, gap
				end
			end
			local home = table.remove(left, index) :: Map.Home
			local take = math.min(papersAt(home), tuning.Papers[2] - total)
			if take <= 0 or walked + bestGap > limit then
				break
			end
			table.insert(out, { home = home, papers = take })
			total += take
			walked += bestGap
			x, z = home.park.x, home.park.z
		end
		return out, total
	end
	-- Every street may start a round that holds Papers[1] within the budget; one of them by chance, the ones with more
	-- papers more likely.
	local rounds: { { Door } } = {}
	local weights: { number } = {}
	local weight = 0
	for _, street in streets do
		local doors, papers = build(street)
		if papers >= tuning.Papers[1] then
			table.insert(rounds, doors)
			table.insert(weights, street.papers)
			weight += street.papers
		end
	end
	if #rounds == 0 then
		return {}
	end
	local roll = r() * weight
	for n, doors in rounds do
		roll -= weights[n]
		if roll < 0 then
			return doors
		end
	end
	return rounds[#rounds]
end

-- 5.3 review: does the business deliver anywhere `low` … `high` (manhattan) from (x, z)? (The board offers it on a
-- tier, or on foot / by bike, only then: no ice cream "nearby" 1,700 studs away, no cake run across the map.) A
-- business without a `to` (any address) always does.
function Deliveries.reaches(business: Config.BusinessDef, x: number, z: number, low: number, high: number, allow: ((Map.Address) -> boolean)?): boolean
	if not business.to then
		return true
	end
	for _, target in Deliveries.targets(business) do
		local address = target.address
		local d = Map.manhattan(x, z, address.x, address.z)
		if d >= low and d <= high and (not allow or allow(address)) then
			return true
		end
	end
	return false
end

return Deliveries
