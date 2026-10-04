-- Test of the icon set (shared/Icons.luau) in the standalone Luau CLI: every picture in art/assets.json and
-- art/ui/assets.json has its place for the asset id, every gun, item, kind of cargo, business look and landmark of
-- the game maps to an icon that exists (or explicitly to none), and an empty id means "use the fallback".
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Icons = require("./Icons")
local Map = require("./Map")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

-- The names in art/assets.json and art/ui/assets.json (copied here: the test reads nothing from disk).
local ART = {
	"weapon_pistol", "weapon_smg", "weapon_shotgun", "weapon_rifle", "weapon_minigun", "weapon_launcher",
	"weapon_revolver", "weapon_carbine",
	"cargo_crate", "cargo_ammo", "cargo_sack", "cargo_barrel", "cargo_icebox", "cargo_furniture", "cargo_soup",
	"cargo_horse", "cargo_kid", "cargo_parcel", "cargo_pizza", "cargo_medicine",
	"item_repair", "item_medkit", "item_nitro", "item_molotov", "item_mine",
	"map_depot", "map_dealer", "map_guns", "map_mechanic", "map_supplies", "map_school", "map_army", "map_icecream",
	"map_movers", "map_farm", "map_ranch", "map_gas", "map_stables", "map_fueldepot", "map_lodge", "map_radio",
	"map_docks",
	"zombie_delivery_logo",
	"menu_background", -- art/ui/assets.json (with the logo again)
}

-- Every picture has its id slot, and the set has nothing else.
local inArt = {}
for _, name in ART do
	inArt[name] = true
	check(`{name} is in Icons.Ids`, Icons.Ids[name] ~= nil)
end
local count = 0
for name, id in Icons.Ids do
	count += 1
	check(`{name} is a picture in art/`, inArt[name] == true)
	check(`{name} is empty or an asset id`, id == "" or string.match(id, "^rbxassetid://%d+$") ~= nil, id)
end
check("44 pictures", count == 44, count)

-- get: nil for empty, unknown or no name; the id when it is filled in.
check("an empty id gives nil", Icons.Ids.weapon_pistol ~= "" or Icons.get("weapon_pistol") == nil)
check("an unknown name gives nil", Icons.get("weapon_banana") == nil)
check("no name gives nil", Icons.get(nil) == nil)
do
	local saved = Icons.Ids.map_depot
	Icons.Ids.map_depot = "rbxassetid://123"
	check("a filled-in id is returned", Icons.get("map_depot") == "rbxassetid://123")
	Icons.Ids.map_depot = saved
end

-- An icon name a helper gave: it must exist ("none" = nil is allowed only where the expectation says so).
local function exists(name: string?): boolean
	return name ~= nil and Icons.Ids[name] ~= nil
end

for _, def in Config.Weapons do
	check(`gun {def.id} has an icon`, exists(Icons.weapon(def.id)), Icons.weapon(def.id))
end
for _, def in Config.CarGuns do
	check(`car gun {def.id}: none (the emoji)`, Icons.weapon(def.id) == nil)
end
for _, def in Config.Items do
	check(`item {def.id} has an icon`, exists(Icons.item(def.id)), Icons.item(def.id))
end
for kind, info in Config.Cargo.Kinds do
	check(`cargo kind {kind} has an icon`, exists(Icons.cargo(kind)), Icons.cargo(kind))
	check(`cargo look {info.look} has an icon`, exists(Icons.cargo(info.look)), Icons.cargo(info.look))
end
for _, def in Config.JobTypes do
	check(`job type {def.id}: its pieces have an icon`, exists(Icons.cargo(def.itemKind)), def.itemKind)
end
for _, business in Config.Jobs.Businesses do
	check(`business {business.id}: kind {business.kind} has an icon`, exists(Icons.cargo(business.kind)))
	check(`business {business.id}: look {business.look} has an icon`, exists(Icons.cargo(business.look)), business.look)
end
check("pizza is a pizza", Icons.cargo("pizza") == "cargo_pizza")
check("bread is a sack", Icons.cargo("bread") == "cargo_sack")
check("tools are a crate", Icons.cargo("tools") == "cargo_crate")
check("the vaccine is medicine", Icons.cargo("vaccine") == "cargo_medicine")
check("an unknown cargo: none", Icons.cargo("spaceship") == nil)

for _, landmark in Map.Landmarks do
	check(`landmark {landmark.id} has an icon`, exists(Icons.landmark(landmark.id)), Icons.landmark(landmark.id))
end
for _, employer in Config.Employers do
	check(`employer {employer.id} has a map icon`, exists(Icons.landmark(employer.id)))
end
for _, place in Map.Places do
	check(`place {place.id} has a map icon`, exists(Icons.landmark(place.id)), place.id)
end
for id in Map.Shops do
	check(`shop {id} has a map icon`, exists(Icons.landmark(id)))
end
check("an unknown landmark: none", Icons.landmark("moon") == nil)

-- Every map icon is used by a landmark.
local used = {}
for _, landmark in Map.Landmarks do
	used[Icons.landmark(landmark.id) or ""] = true
end
for name in Icons.Ids do
	if string.sub(name, 1, 4) == "map_" then
		check(`{name} marks a landmark`, used[name] == true)
	end
end


if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
