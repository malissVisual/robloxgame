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

-- The names in art/assets.json, art/ui/assets.json and art/signs/assets.json (copied here: the test reads nothing from disk).
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
	-- art/signs/assets.json (the building signs)
	"sign_depot", "sign_dealer", "sign_guns", "sign_mechanic", "sign_supplies", "sign_repairs", "sign_garage_rented",
	"sign_garage_south", "sign_garage_harbor", "sign_garage_north", "sign_garage_downtown", "sign_school", "sign_army",
	"sign_icecream", "sign_movers", "sign_farm", "sign_ranch", "sign_clinic", "sign_gas", "sign_bank", "sign_pharmacy",
	"sign_market", "sign_firestation", "sign_police", "sign_cityhall", "sign_dispatchtower", "sign_harborpoint",
	"sign_docks", "sign_warehouse", "sign_fueldepot", "sign_powerplant", "sign_waterworks", "sign_trainyard",
	"sign_radio", "sign_lodge", "sign_stables", "sign_airfield", "sign_lab", "sign_prison", "sign_lighthouse",
	"sign_camp", "sign_stadium", "sign_hilltop", "sign_oceanview", "sign_pinecrest", "sign_lakeside", "sign_sunset",
	"sign_maple", "sign_oak", "sign_birch", "sign_elm", "sign_office_harbor", "sign_office_tower",
	"sign_office_penthouse",
	-- 5.0: art/icons (the kit, the phone's apps)
	"kit_shoes", "kit_jacket", "kit_cart", -- (6.6: no backpacks: kit_backpack / kit_bigpack's pictures stay in art/icons unused)
	"kit_kevlar", "kit_heavy", -- 6.0, the vests
	"kit_bag", -- 6.0: the plastic bag (its picture is still to come: the emoji meanwhile)
	"kit_tote", "kit_thermal", "kit_padded", "kit_duffel", -- 6.4, the bags (the emoji meanwhile)
	"kit_hivis", -- 6.0.1: the Courier Vest (the emoji 🦺 meanwhile)
	"item_energy", "kit_bat", -- 6.7: the Energy Drink and the Baseball Bat (their pictures still to come: the emoji meanwhile)
	"app_orders", "app_board", "app_career", "app_shop", "app_map", "app_messages", "app_bank", "app_settings",
	-- 5.1, art/icons (Codex's bike art; ids empty until uploaded)
	"bike_rust", "bike_city", "bike_cargo", "bike_ebike", "gear_basket", "gear_panniers", "gear_trailer", "map_bikes",
	-- 5.4, art/icons (Codex's fuel art; ids empty until uploaded; map_gas is above)
	"jerrycan", "fuel",
	-- 5.x polish
	"map_bus",
	"map_zip",
	"map_rental",
	"map_shortcut",
	"map_bank",
	"map_clinic",
	"map_pharmacy",
	"map_warehouse",
	"map_firestation",
	"map_police",
	"map_waterworks",
	"map_lab",
	"map_camp",
	"map_stadium",
	"map_luigis",
	"map_dailybread",
	"map_lastbite",
	"map_wokdead",
	"map_grindhouse",
	"map_postoffice",
	"map_dailyundead",
	"map_boltnail",
	"map_volt",
	"map_secondlife",
	"map_bloom",
	"weapon_reyes",
	"weapon_lever",
	"weapon_goldpistol",
	"weapon_deadend",

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
check("158 pictures", count == 158, count) -- (6.0: + the two vests and the bag; 6.0.1: + the Courier Vest; 6.4: + four bags; 6.6: − the two backpacks; 6.7: + the energy drink and the bat)

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

-- 5.0: every piece of kit and every app of the phone has an icon (the emoji while its id is empty).
for _, def in Config.Kit do
	check(`kit {def.id} has an icon`, exists(Icons.kit(def.id)), Icons.kit(def.id))
end
for _, id in { "orders", "board", "career", "shop", "map", "messages" } do
	check(`phone app {id} has an icon`, exists(Icons.app(id)), Icons.app(id))
end
check("an unknown kit or app: none", Icons.kit("jetpack") == nil and Icons.app("casino") == nil and Icons.kit(nil) == nil)
check("a kit icon while its id is empty: the emoji", Icons.Ids.kit_tote ~= "" or Icons.get(Icons.kit("tote")) == nil)
check("6.6: the bag kiosk's marker is the plastic bag's picture", Icons.landmark("bags") == "kit_bag")
-- 5.1: the bikes and the bike gear have pictures (the car gear: the emoji).
check("the bike shop's marker", Icons.landmark("bikes") == "map_bikes")
check("the four bikes", Icons.bike("rustbike") == "bike_rust" and Icons.bike("citybike") == "bike_city" and Icons.bike("cargobike") == "bike_cargo"
	and Icons.bike("ebike") == "bike_ebike" and Icons.bike("van") == nil and Icons.bike(nil) == nil)
for _, gear in Config.Gear do
	check(`gear {gear.id}: {if gear.bikeOnly then "its picture" else "the emoji"}`, if gear.bikeOnly then exists(Icons.gear(gear.id)) else Icons.gear(gear.id) == nil)
end

-- The building signs: every shop, employer, tower and home has one (two places share their employer's), the garages
-- and the homes are square badges, the rest 4 : 1 boards. (5.1: Spoke & Chain has no sign picture: its board is the
-- contract look, text only.)
local NO_SIGN_ART: { [string]: boolean } = { bikes = true, bags = true } -- (6.6: ZDC Bags' board is the contract look too)
for id in Map.Shops do
	if NO_SIGN_ART[id] then
		check(`shop {id}: no sign picture (the text board)`, Icons.sign(id) == nil)
	else
		check(`shop {id} has a sign`, exists(Icons.sign(id)))
	end
end
for _, employer in Config.Employers do
	check(`employer {employer.id} has a sign`, exists(Icons.sign(employer.id)))
end
for id in Map.Towers do
	check(`tower {id} has a sign`, exists(Icons.sign(id)) and Icons.signAspect(id) == 4)
end
for _, def in Config.Estate.Properties do
	check(`estate {def.id} has a sign`, exists(Icons.sign(def.id)))
	local square = def.kind ~= "office"
	check(`estate {def.id}: its sign's shape`, Icons.signAspect(def.id) == (if square then 1 else 4), Icons.signAspect(def.id))
end
check("the base uses the army's sign", Icons.sign("base") == "sign_army")
check("frosty uses the ice cream sign", Icons.sign("frosty") == "sign_icecream")
check("the depot's sign is a board", Icons.signAspect("depot") == 4)
check("an unknown building: no sign", Icons.sign("moon") == nil and Icons.sign(nil) == nil)
check("a sign while its id is empty: the text", Icons.Ids.sign_depot ~= "" or Icons.get(Icons.sign("depot")) == nil)

-- Uploaded landmark art must be routed. New landmark art is staged while empty, with the borrowed icon retained.
local STAGED_LANDMARKS = {
	"bank", "clinic", "pharmacy", "warehouse", "firestation", "police", "waterworks", "lab", "camp", "stadium",
	"luigis", "dailybread", "lastbite", "wokdead", "grindhouse", "postoffice", "dailyundead", "boltnail", "volt", "secondlife", "bloom",
}
local staged, known = {}, {}
for _, landmark in Map.Landmarks do known[landmark.id] = true end
for _, id in STAGED_LANDMARKS do
	check("new art belongs to a real landmark: " .. id, known[id] == true)
	staged["map_" .. id] = true
end
local TRANSPORT = { map_bus = true, map_zip = true, map_rental = true, map_shortcut = true }
local used = {}
for _, landmark in Map.Landmarks do
	used[Icons.landmark(landmark.id) or ""] = true
end
-- (6.12.7: the bikes are Dead End Motors' BIKES counter, no landmark of their own: the shop's marker, map_bikes, stays
-- routed through Map.Shops.bikes)
for id in Map.Shops do
	used[Icons.landmark(id) or ""] = true
end
for name in Icons.Ids do
	if string.sub(name, 1, 4) == "map_" then
		if TRANSPORT[name] then
			check(name .. " resolves as a dynamic transport marker", Icons.landmark(string.sub(name, 5)) == name)
		else
			check(name .. " is routed or has pending upload for its real landmark", used[name] == true or (staged[name] and Icons.Ids[name] == ""))
		end
	end
end


if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
