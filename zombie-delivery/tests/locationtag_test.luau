-- Logic test of the location tag (shared/LocationTags.luau) in the standalone Luau CLI: every landmark gets a tag with
-- a sign-like name and a truthful second line (the depot reads ZOMBIE DELIVERY CO. / DEPOT · JOBS · GARAGE), the
-- distance to a point and to a yard's edge, the caption's rule (comes within NEAR, goes beyond FAR or after HOLD, the
-- nearest known place only, once per COOLDOWN and not again before you left, not while canStart is off, a place the
-- banner announced waits) and where it sits on the screen (the first spot clear of the HUD).
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Map = require("./Map")
local LocationTags = require("./LocationTags")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local L = LocationTags

-- ── The tags ───────────────────────────────────────────────────────────────

local tags = L.build()
check("every landmark has a tag", #tags == #Map.Landmarks, `{#tags}/{#Map.Landmarks}`)
local byId: { [string]: LocationTags.Tag } = {}
local badName, badSub = {}, {}
for _, t in tags do
	byId[t.id] = t
	if t.name == "" or string.find(t.name, "[()]") then
		table.insert(badName, t.id)
	end
	if t.sub and (t.sub == "" or string.upper(t.sub) ~= t.sub) then
		table.insert(badSub, t.id)
	end
end
check("every name is a sign's name (no brackets)", #badName == 0, table.concat(badName, ", "))
check("every second line is in caps", #badSub == 0, table.concat(badSub, ", "))
local depot = byId.depot
check("the depot reads like its sign", depot ~= nil and depot.name == "Zombie Delivery Co." and depot.sub == "DEPOT · JOBS · GARAGE", depot and depot.name)
check("a shop says what it sells", byId.guns ~= nil and byId.guns.sub == "GUN SHOP" and byId.dealer.sub == "CARS · VANS · BIKES")
-- 6.12.7: one shop for the cars and the bikes: Dead End Motors names them both, Spoke & Chain has no tag of its own.
check("6.12.7: no Spoke & Chain tag, Dead End Motors is the bikes' place", byId.bikes == nil and byId.dealer ~= nil and byId.dealer.name == "Dead End Motors"
	and (function()
		for _, t in tags do
			if string.find(t.name, "Spoke", 1, true) then
				return false
			end
		end
		return true
	end)())
local kinds: { [string]: string } = {}
for _, landmark in Map.Landmarks do
	kinds[landmark.id] = landmark.kind
end
local employers, shopsNear = 0, true
for _, t in tags do
	if kinds[t.id] == "employer" then
		employers += 1
		check(`employer {t.id} says EMPLOYER`, t.sub == "EMPLOYER", t.sub)
	end
	local kiosk = Map.Shops[t.id] and Map.Shops[t.id].radius -- (6.6: ZDC Bags, a kiosk: near from its own radius)
	if kinds[t.id] == "shop" and kiosk then
		shopsNear = shopsNear and t.near == kiosk and t.far > t.near and t.sub ~= nil
	elseif kinds[t.id] == "shop" then
		shopsNear = shopsNear and t.near == L.SHOP_NEAR and t.far == L.SHOP_FAR and t.sub ~= nil
	else
		shopsNear = shopsNear and t.near == L.NEAR and t.far == L.FAR
	end
	check(`{t.id}: far beyond near (hysteresis)`, t.far > t.near)
end
check("there are employers", employers > 0)
check("a shop (its block's centre) is near from SHOP_NEAR, the rest from NEAR", shopsNear)
check("a shop's front (the road beside its block) is within SHOP_NEAR", Map.Cell / 2 <= L.SHOP_NEAR, Map.Cell / 2)
local bags = byId.bags
-- (the spawn: 26 south of the depot's middle, server/World.luau DepotSpawn; 6.11: the depot is Map.Depot)
check("6.6: ZDC Bags says BAGS, near only at its kiosk (not from the spawn)", bags ~= nil and bags.sub == "BAGS" and bags.near < LocationTags.distance(bags, Map.Depot.x, Map.Depot.z + 26), bags and bags.near)
local garage = byId.garage_rented
check("a garage says GARAGE", garage ~= nil and garage.sub == "GARAGE", garage and garage.sub)
check("an office tower says OFFICES", byId.dispatchtower ~= nil and byId.dispatchtower.sub == "OFFICES")
local lighthouse = byId.lighthouse
check("a place with nothing sure to say has no second line", lighthouse ~= nil and lighthouse.sub == nil)
check("a place with a yard is measured to the yard", lighthouse ~= nil and lighthouse.area ~= nil)

-- ── The distance ───────────────────────────────────────────────────────────

local point: LocationTags.Tag = { id = "a", name = "A", x = 0, z = 0, near = 45, far = 70 }
local yard: LocationTags.Tag = { id = "y", name = "Y", x = 500, z = 0, area = { x0 = 400, z0 = -100, x1 = 600, z1 = 100 }, near = 45, far = 70 }
check("distance to a point", math.abs(L.distance(point, 30, 40) - 50) < 1e-9)
check("inside a yard: 0", L.distance(yard, 500, 50) == 0)
check("beside a yard: to its edge", math.abs(L.distance(yard, 380, 0) - 20) < 1e-9)
check("off a yard's corner: to the corner", math.abs(L.distance(yard, 370, -140) - 50) < 1e-9)

-- ── The rule ───────────────────────────────────────────────────────────────

local list = { point, yard }
local s = L.new()
local action, t = L.step(s, list, 0, 100, 0, true)
check("far from everything: nothing", action == nil and t == nil)
action, t = L.step(s, list, 0, 40, 1, false)
check("near, but canStart off (a fast car, the HUD hidden): nothing", action == nil)
action, t = L.step(s, list, 0, 40, 1, true)
check("near: it comes", action == "show" and t == point)
action, t = L.step(s, list, 0, 60, 2, false)
check("between near and far: it stays (even when it could not start)", action == nil and t == point)
action, t = L.step(s, list, 0, 75, 3, true)
check("beyond far: it goes", action == "hide" and t == point)
action = L.step(s, list, 0, 40, 10, true)
check("back within the cooldown: nothing", action == nil)
action = L.step(s, list, 0, 40, 1 + L.COOLDOWN + 1, true)
check("back after the cooldown: it comes again", action == "show")
action = L.step(s, list, 0, 40, 1 + L.COOLDOWN + 1 + L.HOLD, true)
check("after HOLD seconds it goes, though still near", action == "hide")
action = L.step(s, list, 0, 40, 1 + 3 * L.COOLDOWN, true)
check("not again before you left it (beyond far)", action == nil)
L.step(s, list, 0, 80, 1 + 3 * L.COOLDOWN + 1, true)
action = L.step(s, list, 0, 40, 1 + 3 * L.COOLDOWN + 2, true)
check("left and came back after the cooldown: it comes", action == "show")
check("drop takes it off", L.drop(s) == point and s.current == nil)

-- The nearest, the known only, the yard, the banner's mark.
local s2 = L.new()
local close: LocationTags.Tag = { id = "b", name = "B", x = 60, z = 0, near = 45, far = 70 }
action, t = L.step(s2, { point, close }, 35, 0, 0, true)
check("two near: the nearest", action == "show" and t == close)
local s3 = L.new()
action, t = L.step(s3, { point, close }, 35, 0, 0, true, function(id: string): boolean
	return id ~= "b"
end)
check("an unknown place is skipped for a known one", action == "show" and t == point)
local s4 = L.new()
action, t = L.step(s4, list, 360, 0, 0, true)
check("40 studs from a yard's edge: it comes", action == "show" and t == yard)
local s5 = L.new()
L.mark(s5, "a", 0)
action = L.step(s5, list, 0, 10, 5, true)
check("a place the banner just announced waits its cooldown", action == nil)
action = L.step(s5, list, 0, 10, L.COOLDOWN + 1, true)
check("... and then comes", action == "show")

-- A walk through the real map: up to the depot, it names it (6.11: its yard opens to Bone St, south of its middle).
local s6 = L.new()
local real = L.build()
action, t = L.step(s6, real, Map.Depot.x, Map.Depot.z + 60, 0, true)
check("on the street in front of the depot: ZOMBIE DELIVERY CO.", action == "show" and t ~= nil and t.id == "depot", t and t.id)
-- 6.11: by the pond in the middle, the park names itself (and the safe zone); in front of a shop round it, the shop.
local park = byId.park
check("6.11: the Central Park says SAFE ZONE", park ~= nil and park.name == "Central Park" and park.sub == "SAFE ZONE", park and park.sub)
action, t = L.step(L.new(), real, Map.Park.x, Map.Park.z + 24, 0, true)
check("6.11: on the path round the pond: CENTRAL PARK", action == "show" and t ~= nil and t.id == "park", t and t.id)
action, t = L.step(L.new(), real, Map.Park.x, Map.Park.z - 85, 0, true)
-- 6.12.2: Last Stop Supplies is the GEAR counter of the gear stall at the depot; its old building is no shop
check("6.12.2: on the kerb in front of Last Stop's old building, across Bone St from the park: no shop's tag", t == nil or t.id ~= "supplies", t and t.id)
local gear = Map.Shops.supplies
action, t = L.step(L.new(), real, gear.x + 3, gear.z, 0, true)
check("6.12.2: at the gear stall's GEAR counter: LAST STOP SUPPLIES", action == "show" and t ~= nil and t.id == "supplies" and t.sub == "GEAR", t and t.id)
action, t = L.step(L.new(), real, Map.Shops.bags.x + 3, Map.Shops.bags.z, 0, true)
check("6.12.2: at its BAGS counter: ZDC BAGS", action == "show" and t ~= nil and t.id == "bags", t and t.id)

-- ── Where it sits ──────────────────────────────────────────────────────────

local function rect(x0: number, y0: number, x1: number, y1: number): LocationTags.Rect
	return { x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
end
local left = rect(16, 600, 300, 650)
local top = rect(500, 16, 800, 66)
check("clear on the left: the left", L.place({ left, top }, { rect(16, 660, 260, 900) }, 1300, 900) == 1)
check("the left touches the HUD: top centre", L.place({ left, top }, { rect(16, 640, 260, 900) }, 1300, 900) == 2)
check("off the screen: the next", L.place({ rect(16, -20, 300, 30), top }, {}, 1300, 900) == 2)
check("nothing clear: the first", L.place({ left, top }, { rect(0, 0, 1300, 900) }, 1300, 900) == 1)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
