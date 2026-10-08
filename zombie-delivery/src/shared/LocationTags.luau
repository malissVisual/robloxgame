--!strict
-- 4.3: the location tag's choice (client/LocationTag.luau shows it): when you come up to a building, a quiet caption
-- names it ("■ WRENCH GARAGE" over "UPGRADES · REPAIRS"). This module holds what each place says and the rule of when
-- the caption comes and goes; the client only asks it four times a second and draws the answer.
--
--   * The places are Map.Landmarks (the shops, the employers, the mission places, the towers, the estate, 5.3: the
--     storefronts of Map.Venues). The depot reads ZOMBIE DELIVERY CO. like its sign. The second line comes from the
--     landmark's kind (a shop says what it sells, an employer EMPLOYER, a garage GARAGE, a storefront its kind: PIZZERIA,
--     PHARMACY ...); a place with nothing sure to say has none.
--   * A shop's point is its block's centre (you use a shop within Map.ShopRadius of it), so a shop is near from
--     SHOP_NEAR (6.6: a kiosk with its own radius, Map.Shops' `radius`: from that, its point is its counter); a place
--     with a yard (Map.Yards: the base, the farm, the prison ...) is measured to the yard's edge;
--     everything else to its point (a door, the road in front).
--   * Near (NEAR studs, horizontal) and the caption comes; it goes when you are farther than FAR (hysteresis) or after
--     HOLD seconds. The nearest place only, each at most once per COOLDOWN seconds, and not again before you have
--     left it (beyond FAR). The client starts one only on foot or in a car slower than MAX_SPEED, while the HUD shows.
--
-- Pure Luau (tests/locationtag_test.luau runs it in the plain Luau CLI).

local Config = require(script.Parent.Config)
local Map = require(script.Parent.Map)

local LocationTags = {}

LocationTags.NEAR = 45 -- studs (horizontal): this close and the caption comes
LocationTags.FAR = 70 -- studs: farther and it goes
LocationTags.SHOP_NEAR = 75 -- a shop's point is its block's centre: its front is about this far out
LocationTags.SHOP_FAR = 100
LocationTags.HOLD = 4.5 -- seconds on screen at most
LocationTags.COOLDOWN = 90 -- seconds before the same place shows again
LocationTags.MAX_SPEED = 25 -- studs/s: a car faster than this passes by without a caption

export type Box = { x0: number, z0: number, x1: number, z1: number }

export type Tag = {
	id: string, -- the landmark's id
	name: string, -- as on the sign (the client writes it in caps)
	sub: string?, -- the second line, already in caps (nil: none)
	x: number,
	z: number,
	area: Box?, -- a yard: the distance is to its edge (0 inside)
	near: number,
	far: number,
}

export type State = {
	current: Tag?, -- the tag on screen
	since: number, -- when it came
	seen: { [string]: number }, -- when each place last showed (or was announced by the discovery banner)
	last: string?, -- the last place shown, until you have left it (beyond its far)
}

-- What the second line says.
local SHOP_SUB: { [string]: string } = {
	depot = "DEPOT · JOBS · GARAGE",
	dealer = "CAR DEALER",
	guns = "GUN SHOP",
	mechanic = "UPGRADES · REPAIRS",
	repairs = "REPAIR SHOP",
	supplies = "GEAR", -- (6.12.2: the gear stall's GEAR counter, near from its radius)
	bikes = "BIKES · BIKE GEAR", -- 5.1
	bags = "BAGS", -- 6.6: the depot's bag kiosk (6.12.2: the gear stall's BAGS counter)
}
local PLACE_SUB: { [string]: string } = {
	park = "SAFE ZONE", -- 6.11: the Central Park in the middle of it (Map.Park)
	dispatchtower = "OFFICES",
	harborpoint = "OFFICES",
	sunsethills = "HILLTOP MANSION",
	earl = "USED VANS", -- 5.0, Earl's Used Wheels (Config.VanQuest)
	gas_downtown = "GAS STATION", -- 5.4, the new gas stations (Map.GasStations)
	gas_harbor = "GAS STATION",
	gas_suburbs = "GAS STATION",
}
local ESTATE_SUB: { [string]: string } = {
	garage = "GARAGE",
	villa = "VILLA",
	mansion = "MANSION",
	house = "HOUSE",
}
-- The name as on the building's sign, where the map's list says it otherwise.
local NAMES: { [string]: string } = {
	depot = "Zombie Delivery Co.",
}

-- The second line for a landmark (nil when there is nothing sure to say).
function LocationTags.subtitle(landmark: Map.Landmark): string?
	if landmark.kind == "shop" then
		return SHOP_SUB[landmark.id] or "SHOP"
	elseif landmark.kind == "employer" then
		return "EMPLOYER"
	end
	if PLACE_SUB[landmark.id] then
		return PLACE_SUB[landmark.id]
	end
	-- 5.3: a storefront (Map.Venues; the older ones are places: the pharmacy, FreshMart, the bank, the warehouse) says
	-- what kind it is
	local venue = Map.venue(landmark.id)
	if venue then
		return venue.sub
	end
	for _, def in Config.Estate.Properties do
		if def.id == landmark.id then
			return ESTATE_SUB[def.kind]
		end
	end
	return nil
end

-- Every landmark's tag.
function LocationTags.build(): { Tag }
	local yards: { [string]: Box } = {}
	for _, yard in Map.Yards do
		yards[yard.id] = { x0 = yard.x0, z0 = yard.z0, x1 = yard.x1, z1 = yard.z1 }
	end
	local tags: { Tag } = {}
	for _, landmark in Map.Landmarks do
		-- (6.6: a kiosk with its own radius, ZDC Bags, is near from that radius, not from a block's front)
		local kiosk = Map.Shops[landmark.id]
		local radius = if landmark.kind == "shop" and kiosk then kiosk.radius else nil
		local shop = landmark.kind == "shop" and radius == nil
		local name = NAMES[landmark.id] or (string.gsub(landmark.name, "%s*%b()", ""))
		table.insert(tags, {
			id = landmark.id,
			name = name,
			sub = LocationTags.subtitle(landmark),
			x = landmark.x,
			z = landmark.z,
			area = yards[landmark.id],
			near = if radius then radius elseif shop then LocationTags.SHOP_NEAR else LocationTags.NEAR,
			far = if radius then radius + (LocationTags.FAR - LocationTags.NEAR) elseif shop then LocationTags.SHOP_FAR else LocationTags.FAR,
		})
	end
	return tags
end

-- Studs (horizontal) from (x, z) to the tag's place: to its yard's edge (0 inside) or to its point.
function LocationTags.distance(tag: Tag, x: number, z: number): number
	local area = tag.area
	if area then
		local dx = math.max(area.x0 - x, 0, x - area.x1)
		local dz = math.max(area.z0 - z, 0, z - area.z1)
		return math.sqrt(dx * dx + dz * dz)
	end
	local dx, dz = x - tag.x, z - tag.z
	return math.sqrt(dx * dx + dz * dz)
end

-- The nearest tag within its near distance that `known` allows (nil: all), and how far it is.
function LocationTags.nearest(tags: { Tag }, x: number, z: number, known: ((id: string) -> boolean)?): (Tag?, number)
	local best: Tag? = nil
	local bestDistance = math.huge
	for _, tag in tags do
		local d = LocationTags.distance(tag, x, z)
		if d <= tag.near and d < bestDistance and (not known or known(tag.id)) then
			best, bestDistance = tag, d
		end
	end
	return best, bestDistance
end

function LocationTags.new(): State
	return { current = nil, since = 0, seen = {}, last = nil }
end

-- The place was just shown elsewhere (the "new location" banner): it waits COOLDOWN like a shown one.
function LocationTags.mark(state: State, id: string, now: number)
	state.seen[id] = now
end

-- The caption goes now (the HUD hid, a window opened, the character died). Returns the tag that was on screen.
function LocationTags.drop(state: State): Tag?
	local current = state.current
	state.current = nil
	return current
end

-- One check at (x, z), `now` seconds: "show" (a tag comes), "hide" (the one on screen goes) or nil (nothing changes),
-- with the tag. `canStart`: a new one may come (on foot or slow, the HUD up, no banner). `known`: the places the
-- player has discovered (nil: all).
function LocationTags.step(state: State, tags: { Tag }, x: number, z: number, now: number, canStart: boolean, known: ((id: string) -> boolean)?): (string?, Tag?)
	local current = state.current
	if current then
		local away = LocationTags.distance(current, x, z) > current.far
		if away or now - state.since >= LocationTags.HOLD then
			state.current = nil
			if away then
				state.last = nil -- (left it: it may come again after its cooldown)
			end
			return "hide", current
		end
		return nil, current
	end
	-- Left the last one: it may come again (after its cooldown).
	if state.last then
		for _, tag in tags do
			if tag.id == state.last then
				if LocationTags.distance(tag, x, z) > tag.far then
					state.last = nil
				end
				break
			end
		end
	end
	if not canStart then
		return nil, nil
	end
	local tag = LocationTags.nearest(tags, x, z, known)
	if not tag or tag.id == state.last then
		return nil, nil
	end
	local seen = state.seen[tag.id]
	if seen and now - seen < LocationTags.COOLDOWN then
		return nil, nil
	end
	state.current = tag
	state.since = now
	state.seen[tag.id] = now
	state.last = tag.id
	return "show", tag
end

-- ── Where it sits on the screen ──────────────────────────────────────────────
-- Screen rectangles in pixels (x right, y down).
export type Rect = { x0: number, y0: number, x1: number, y1: number }

local function overlap(a: Rect, b: Rect): boolean
	return math.min(a.x1, b.x1) - math.max(a.x0, b.x0) > 0 and math.min(a.y1, b.y1) - math.max(a.y0, b.y0) > 0
end

-- The first of `candidates` that lies inside the W × H screen and clear of every obstacle (the HUD's groups, the
-- touch buttons); none clear: the first. Returns its index.
function LocationTags.place(candidates: { Rect }, obstacles: { Rect }, W: number, H: number): number
	for index, candidate in candidates do
		local fits = candidate.x0 >= 0 and candidate.y0 >= 0 and candidate.x1 <= W and candidate.y1 <= H
		if fits then
			for _, obstacle in obstacles do
				if overlap(candidate, obstacle) then
					fits = false
					break
				end
			end
		end
		if fits then
			return index
		end
	end
	return 1
end

return LocationTags
